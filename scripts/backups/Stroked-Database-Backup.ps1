#Requires -Version 5.1
<#
Stroked database backup component, version 1.0 (2026-11-20).
Reads the hosted database; never restores or changes production settings.
Only encrypted output enters OneDrive. Images/source/provider settings are
separate components, and a successful isolated restore is still required.
#>
[CmdletBinding()]
param(
    [switch]$UseExistingExports,
    [string]$DestinationFolder = '',
    [string]$CliPath = ''
)

function Invoke-StrokedNative {
    param([string]$Program, [string[]]$Arguments, [string]$Step)
    # In Windows PowerShell 5.1, redirected native stderr can become an
    # ErrorRecord. Capture both streams without echoing secrets or SQL rows.
    $previousPreference = $ErrorActionPreference
    $LASTEXITCODE = -1
    try {
        $ErrorActionPreference = 'Continue'
        $captured = @(& $Program @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) {
        throw "$Step failed (exit $code). Check Docker and the Supabase login; no new backup has been marked saved."
    }
    # Callers must assign this result. Never print its Text property: a root
    # key retrieval intentionally returns confidential text here.
    return [pscustomobject]@{ Text = (($captured | ForEach-Object { [string]$_ }) -join "`n") }
}

function Get-StrokedRootKey {
    param([string]$CapturedText)
    $matchesFound = @([regex]::Matches($CapturedText, '(?<![0-9a-zA-Z])[0-9a-fA-F]{64}(?![0-9a-zA-Z])') |
        ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
    if ($matchesFound.Count -ne 1) {
        throw 'Vault key export returned an unexpected format. Its contents have not been displayed.'
    }
    return $matchesFound[0]
}

function Assert-StrokedNonemptyFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('Missing backup file: ' + [IO.Path]::GetFileName($Path))
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 1) {
        throw ('Empty backup file: ' + [IO.Path]::GetFileName($Path))
    }
}

function Get-StrokedCopyInventory {
    param([string[]]$Paths)
    $tables = @{}
    foreach ($path in $Paths) {
        Assert-StrokedNonemptyFile $path
        $inCopy = $false
        $currentTable = ''
        $complete = $false
        $reader = [IO.File]::OpenText($path)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if ($inCopy) {
                    if ($line -eq '\.') { $inCopy = $false }
                    else { $tables[$currentTable] = [long]$tables[$currentTable] + 1 }
                    continue
                }
                if ($line -match '^-- PostgreSQL database dump complete\s*$') { $complete = $true }
                if ($line -match '^COPY\s+(?:"(?<schema>[^"]+)"|(?<schema>[A-Za-z_][A-Za-z0-9_$]*))\.(?:"(?<table>[^"]+)"|(?<table>[A-Za-z_][A-Za-z0-9_$]*))\s+\(.*\)\s+FROM stdin;\s*$') {
                    $currentTable = $Matches.schema + '.' + $Matches.table
                    if ($tables.ContainsKey($currentTable)) { throw "Duplicate COPY table in export: $currentTable" }
                    $tables[$currentTable] = [long]0
                    $inCopy = $true
                }
            }
        }
        finally { $reader.Dispose() }
        if ($inCopy -or -not $complete) {
            throw ('Incomplete SQL data export: ' + [IO.Path]::GetFileName($path))
        }
    }
    return $tables
}

function New-StrokedPrivateDirectory {
    param([string]$Path)
    $null = New-Item -ItemType Directory -Path $Path -ErrorAction Stop
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetOwner($owner)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($owner, $system)) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $null = $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Publish-StrokedCiphertext {
    param([string]$EncryptedPath, [string]$Folder, [string]$Name, [string]$ExpectedHash)
    Assert-StrokedNonemptyFile $EncryptedPath
    if ([IO.Path]::GetFileName($Name) -ne $Name -or -not $Name.EndsWith('.zip.age')) {
        throw 'Invalid encrypted archive filename.'
    }
    if ((Get-FileHash -LiteralPath $EncryptedPath -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'Encrypted archive changed before copying.'
    }
    $final = Join-Path $Folder $Name
    $partial = $final + '.partial'
    $createdPartial = $false
    try {
        # Never overwrite an existing archive, even if a filename is reused.
        [IO.File]::Copy($EncryptedPath, $partial, $false)
        $createdPartial = $true
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $ExpectedHash) {
            throw 'OneDrive folder copy verification failed.'
        }
        [IO.File]::Move($partial, $final)
        $createdPartial = $false
        if ((Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash -ne $ExpectedHash) {
            throw 'Final encrypted archive verification failed.'
        }
        return $final
    }
    finally {
        if ($createdPartial -and (Test-Path -LiteralPath $partial)) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-StrokedDatabaseBackup {
    [CmdletBinding()]
    param([switch]$UseExistingExports, [string]$DestinationFolder = '', [string]$CliPath = '')
    $ErrorActionPreference = 'Stop'
    $projectRef = 'aodywiwkhtxwlscpqnda'
    $started = [DateTime]::UtcNow
    $privateRoot = Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    $work = Join-Path $privateRoot 'database'
    $identity = Join-Path $privateRoot 'recovery-key.txt'
    if (-not $CliPath) { $CliPath = Join-Path $env:USERPROFILE 'StrokedTools\supabase\supabase.exe' }
    if (-not $DestinationFolder) { $DestinationFolder = Join-Path $env:USERPROFILE 'OneDrive\Stroked back up' }
    $lock = $null
    $stage = $null
    $saved = $false
    try {
        Write-Host '1/7 Checking the installed tools and local recovery key...'
        Assert-StrokedNonemptyFile $identity
        Assert-StrokedNonemptyFile $CliPath
        if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) {
            throw 'The Stroked back up OneDrive folder was not found. No output folder has been guessed or created.'
        }
        Assert-StrokedNonemptyFile (Join-Path $DestinationFolder 'Stroked-Recovery-Key.age')
        $age = (Get-Command age.exe -CommandType Application -ErrorAction Stop).Source
        $keygen = (Get-Command age-keygen.exe -CommandType Application -ErrorAction Stop).Source
        try {
            $lock = [IO.File]::Open((Join-Path $privateRoot 'database-backup.lock'),
                [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch { throw 'Another database backup may be running, or its local lock cannot be opened.' }

        $version = (Invoke-StrokedNative $CliPath @('--version') 'Supabase version check').Text.Trim()
        $ageVersion = (Invoke-StrokedNative $age @('--version') 'Age version check').Text.Trim()
        $null = Invoke-StrokedNative $CliPath @('db', 'dump', '--help') 'Database export help check'
        $null = Invoke-StrokedNative $CliPath @('encryption', 'get-root-key', '--help') 'Vault export help check'
        $recipientText = (Invoke-StrokedNative $keygen @('-y', $identity) 'Public recovery recipient check').Text.Trim()
        $recipients = @($recipientText -split '\r?\n' | Where-Object { $_ -match '^age1[0-9a-z]{20,100}$' })
        if ($recipients.Count -ne 1) { throw 'The local age recovery identity could not be validated.' }
        $recipient = $recipients[0]

        $runId = [Guid]::NewGuid().ToString('N')
        $stage = Join-Path $privateRoot ('database-run-' + $runId)
        New-StrokedPrivateDirectory $stage
        $payload = Join-Path $stage 'payload'
        $null = New-Item -ItemType Directory -Path $payload
        $null = New-Item -ItemType Directory -Path $work -Force
        if (-not (Test-Path -LiteralPath (Join-Path $work 'supabase\config.toml') -PathType Leaf)) {
            $null = Invoke-StrokedNative $CliPath @('init', '--workdir', $work) 'Local export workspace setup'
        }
        $common = @(('--remote=' + $projectRef), '--workdir', $work)
        $fileRecords = New-Object 'System.Collections.Generic.List[object]'

        Write-Host '2/7 Preparing the database role, structure and data exports...'
        foreach ($name in @('roles.sql', 'schema.sql', 'data.sql')) {
            $outputPath = Join-Path $payload $name
            $exportStart = [DateTime]::UtcNow.ToString('o')
            if ($UseExistingExports) {
                $source = Join-Path $work $name
                Assert-StrokedNonemptyFile $source
                [IO.File]::Copy($source, $outputPath, $false)
                if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $outputPath).Hash) {
                    throw "Existing export changed while copying: $name"
                }
                $mode = 'existing-export'
                $exportStart = $null
            }
            else {
                $arguments = @('db', 'dump') + $common + @('--file', $outputPath)
                if ($name -eq 'roles.sql') { $arguments += '--role-only' }
                if ($name -eq 'data.sql') {
                    $arguments += @('--data-only', '--use-copy', '-x', 'storage.buckets_vectors', '-x', 'storage.vector_indexes')
                }
                $null = Invoke-StrokedNative $CliPath $arguments ($name + ' export')
                $mode = 'fresh-export'
            }
            Assert-StrokedNonemptyFile $outputPath
            $fileRecords.Add([pscustomobject]@{
                name = $name; mode = $mode; exportStartedUtc = $exportStart
                exportFinishedOrSourceModifiedUtc = (Get-Item -LiteralPath $outputPath).LastWriteTimeUtc.ToString('o')
            })
        }

        Write-Host '3/7 Checking table coverage and preserving migration/schema references...'
        $primaryData = Join-Path $payload 'data.sql'
        $inventory = Get-StrokedCopyInventory @($primaryData)
        $dataPaths = @($primaryData)
        if (-not $inventory.ContainsKey('vault.secrets')) {
            $vaultData = Join-Path $payload 'vault-data.sql'
            $null = Invoke-StrokedNative $CliPath (@('db', 'dump') + $common +
                @('--data-only', '--use-copy', '--schema', 'vault', '--file', $vaultData)) 'Vault data export'
            $dataPaths += $vaultData
            $inventory = Get-StrokedCopyInventory $dataPaths
        }
        $requiredTables = @(
            'public.events', 'public.event_admins', 'public.stroked_v53_profiles',
            'public.stroked_v53_requests', 'public.stroked_v54_rsvps', 'public.stroked_v5_events',
            'auth.users', 'auth.identities', 'auth.mfa_factors',
            'auth.mfa_recovery_code_sets', 'auth.mfa_recovery_codes',
            'storage.buckets', 'storage.objects', 'vault.secrets'
        )
        $missing = @($requiredTables | Where-Object { -not $inventory.ContainsKey($_) })
        if ($missing.Count -gt 0) { throw ('Data export is missing required tables: ' + ($missing -join ', ')) }
        $schemaText = [IO.File]::ReadAllText((Join-Path $payload 'schema.sql'))
        foreach ($table in @('events', 'event_admins', 'stroked_v53_profiles', 'stroked_v53_requests', 'stroked_v54_rsvps', 'stroked_v5_events')) {
            $pattern = '(?im)^CREATE TABLE\s+(?:IF NOT EXISTS\s+)?"?public"?\."?' + [regex]::Escape($table) + '"?\s*\('
            if ($schemaText -notmatch $pattern) { throw "Structure export is missing a required application table: $table" }
        }
        foreach ($spec in @(
            @('managed-schema-reference.sql', 'auth,storage', 'schema'),
            @('migration-history-schema.sql', 'supabase_migrations', 'schema'),
            @('migration-history-data.sql', 'supabase_migrations', 'data')
        )) {
            $arguments = @('db', 'dump') + $common + @('--schema', $spec[1], '--file', (Join-Path $payload $spec[0]))
            if ($spec[2] -eq 'data') { $arguments += @('--data-only', '--use-copy') }
            $null = Invoke-StrokedNative $CliPath $arguments ($spec[0] + ' export')
            Assert-StrokedNonemptyFile (Join-Path $payload $spec[0])
        }
        $historyInventory = Get-StrokedCopyInventory @((Join-Path $payload 'migration-history-data.sql'))
        if (-not $historyInventory.ContainsKey('supabase_migrations.schema_migrations')) {
            throw 'Migration history export did not contain the expected history table.'
        }

        Write-Host '4/7 Saving the Vault recovery key privately, without displaying it...'
        $rootText = (Invoke-StrokedNative $CliPath (@('encryption', 'get-root-key') + $common) 'Vault root key export').Text
        $rootKey = Get-StrokedRootKey $rootText
        [IO.File]::WriteAllText((Join-Path $payload 'vault-root-key.txt'), $rootKey, (New-Object Text.UTF8Encoding($false)))
        $rootText = $null
        $rootKey = $null

        $restoreNotes = @'
STROKED DATABASE COMPONENT - RESTORE TEST PENDING

This archive is confidential. It contains account information and a Vault root
encryption key. Keep it encrypted outside the owner's private restore workspace.

This is not a full site backup: Storage object bytes, source history and provider
settings are separate components. The exports were taken at different times.

Restore only into an isolated local/test instance, with real outgoing email,
payments, webhooks and production cron jobs disabled. Never test by overwriting
the live database. Follow the current Supabase managed-schema restore rules.

roles.sql, schema.sql and data.sql are the primary logical exports. Preserve
grants/default privileges and reapply the latest Stroked security fixes. If
vault-data.sql exists, its non-overlapping tables supplement data.sql.

managed-schema-reference.sql is a reference for Auth/Storage customizations;
do not replay the entire managed schema blindly. Migration history is supplied
separately. Check migrationHistoryAlreadyInPrimaryData in the manifest to avoid
replaying the same history rows twice.

vault-root-key.txt contains the old project's 64-character root key. Vault
ciphertext cannot be recovered with a newly generated root key. Restore that
key only to the isolated destination under the provider's documented process;
never change the live project's root key during a backup or restore drill.

Record a successful isolated restore and an offsite download/decryption check
before treating this backup process as operational.

References:
https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
https://supabase.com/docs/reference/cli/supabase-db-dump
'@
        [IO.File]::WriteAllText((Join-Path $payload 'RESTORE-NOTES.txt'), $restoreNotes)
        $fileInventory = @(Get-ChildItem -LiteralPath $payload -File | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        })
        $manifest = [ordered]@{
            formatVersion = 1; component = 'database'; projectRef = $projectRef
            runId = $runId; startedUtc = $started.ToString('o'); packagedUtc = [DateTime]::UtcNow.ToString('o')
            supabaseCli = $version; ageVersion = $ageVersion; recipient = $recipient
            reusedExistingExports = [bool]$UseExistingExports; primaryExportTimes = @($fileRecords.ToArray())
            atomicDatabaseSnapshot = $false; fullSiteBackup = $false; restoreTestPassed = $false
            excludedComponents = @('Storage object bytes', 'Git source history', 'Provider configuration inventory')
            requiredTableChecks = $requiredTables; copyTableRowCounts = $inventory
            migrationHistoryAlreadyInPrimaryData = $inventory.ContainsKey('supabase_migrations.schema_migrations')
            files = $fileInventory
        }
        $manifestJson = $manifest | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText((Join-Path $payload 'manifest.json'), $manifestJson, (New-Object Text.UTF8Encoding($false)))

        Write-Host '5/7 Compressing and encrypting the database archive...'
        $zip = Join-Path $stage 'database.zip'
        $encrypted = Join-Path $stage 'database.zip.age'
        $verification = Join-Path $stage 'verification.zip'
        $payloadFiles = @(Get-ChildItem -LiteralPath $payload -File | ForEach-Object { $_.FullName })
        Compress-Archive -LiteralPath $payloadFiles -DestinationPath $zip -CompressionLevel Optimal
        Assert-StrokedNonemptyFile $zip
        $null = Invoke-StrokedNative $age @('--encrypt', '-r', $recipient, '-o', $encrypted, $zip) 'Archive encryption'
        Assert-StrokedNonemptyFile $encrypted

        Write-Host '6/7 Decrypting a test copy and comparing its checksum...'
        $null = Invoke-StrokedNative $age @('--decrypt', '-i', $identity, '-o', $verification, $encrypted) 'Archive decryption verification'
        Assert-StrokedNonemptyFile $verification
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $verification -Algorithm SHA256).Hash) {
            throw 'Decrypted archive did not match the original. Nothing has been copied to OneDrive.'
        }

        Write-Host '7/7 Copying only the verified encrypted archive into OneDrive...'
        $name = 'Stroked-database-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ') + '-' + $runId + '.zip.age'
        $cipherHash = (Get-FileHash -LiteralPath $encrypted -Algorithm SHA256).Hash
        $destination = Publish-StrokedCiphertext $encrypted $DestinationFolder $name $cipherHash
        $saved = $true
        # Remove only this run's private staging files; preserve earlier SQL
        # exports, recovery identities and every previous OneDrive archive.
        try { Remove-Item -LiteralPath $stage -Recurse -Force }
        catch { Write-Host 'The private temporary workspace could not be removed; the encrypted copy was verified.' }
        Write-Host ''
        Write-Host 'DATABASE ARCHIVE VERIFIED AND SAVED' -ForegroundColor Green
        Write-Host $name
        Write-Host ('Encrypted bytes: ' + (Get-Item -LiteralPath $destination).Length)
        Write-Host 'OneDrive upload and a full isolated restore still need checking. Images/source/settings are not in this component.'
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if (-not $saved -and $stage) {
            Write-Host 'Backup stopped. Earlier exports and backups are retained; this run is not marked saved.'
            Write-Host 'Its temporary files remain in the private local StrokedBackup folder.'
        }
    }
}

# Dot-sourcing loads helpers for offline tests without contacting Supabase.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-StrokedDatabaseBackup @PSBoundParameters }
    catch {
        Write-Host ('BACKUP STOPPED: ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}
