#Requires -Version 5.1
<#
Stroked image/source/Supabase configuration-reference backup component.
Hosted operations are read-only. No deployment, restore or schedule is created.
The database archive is a separate component. External provider exports and a
complete offsite recovery/restore drill are still required.
#>
[CmdletBinding()]
param([string]$BackupDestination = '', [string]$SupabaseCliPath = '', [string]$HelperPath = '')

function ConvertFrom-StrokedInventoryOutput {
    param([string]$Text)
    # A framed base64 cell survives JSON/table wrappers and native stderr
    # progress without interpreting database strings as commands or paths.
    $cells = @([regex]::Matches($Text, 'STROKED_INVENTORY_V1:([A-Za-z0-9+/=]+):END_STROKED_INVENTORY_V1'))
    if ($cells.Count -ne 1) { throw 'The remote inventory could not be read. Its contents have not been displayed.' }
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cells[0].Groups[1].Value))
        $inventory = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch { throw 'The remote inventory was not valid encoded JSON.' }
    if ($inventory.formatVersion -ne 1 -or $inventory.projectRef -cne 'aodywiwkhtxwlscpqnda' -or
        $null -eq $inventory.buckets -or $null -eq $inventory.objects) {
        throw 'The remote inventory did not match the Stroked project or expected format.'
    }
    return $inventory
}

function Get-StrokedStorageUrl {
    param([string]$Bucket, [string]$ObjectName)
    if (-not $Bucket -or -not $ObjectName -or $Bucket.Contains('/') -or $Bucket.Contains('\')) {
        throw 'Storage inventory contains an invalid bucket or empty object key.'
    }
    # The CLI decodes escaped URL paths. Escape every segment, preserving only
    # the separators: names containing #, ?, %, spaces or Unicode stay keys.
    $parts = @($ObjectName.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) })
    return 'ss:///' + [Uri]::EscapeDataString($Bucket) + '/' + ($parts -join '/')
}

function Assert-StrokedStorageUnchanged {
    param($Before, $After)
    $beforeBuckets = ConvertTo-Json -InputObject @($Before.buckets) -Depth 50 -Compress
    $afterBuckets = ConvertTo-Json -InputObject @($After.buckets) -Depth 50 -Compress
    $beforeObjects = ConvertTo-Json -InputObject @($Before.objects) -Depth 50 -Compress
    $afterObjects = ConvertTo-Json -InputObject @($After.objects) -Depth 50 -Compress
    if ($beforeBuckets -cne $afterBuckets -or $beforeObjects -cne $afterObjects) {
        throw 'Storage changed during the downloads. Run the component again when uploads are quiet; no new archive was marked saved.'
    }
}

function New-StrokedPayloadZip {
    param([string]$Root, [string]$Destination)
    # ZipArchive preserves subdirectories and hidden files. Do not use
    # Compress-Archive on a tree: it silently omits hidden files in PS 5.1.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $directories = New-Object 'System.Collections.Generic.Stack[string]'
    $directories.Push($base)
    $zip = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
    try {
        while ($directories.Count -gt 0) {
            $directory = $directories.Pop()
            foreach ($entry in [IO.Directory]::GetFileSystemEntries($directory)) {
                $attributes = [IO.File]::GetAttributes($entry)
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'The backup payload contains a link or junction; archiving stopped.'
                }
                $full = [IO.Path]::GetFullPath($entry)
                if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'A backup path escaped its private workspace.' }
                if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $directories.Push($full); continue }
                $relative = $full.Substring($base.Length).Replace('\', '/')
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $full, $relative, [IO.Compression.CompressionLevel]::Optimal)
            }
        }
    }
    finally { $zip.Dispose() }
}

function Invoke-StrokedFilesBackup {
    [CmdletBinding()]
    param([string]$BackupDestination = '', [string]$SupabaseCliPath = '')
    $ErrorActionPreference = 'Stop'
    $project = 'aodywiwkhtxwlscpqnda'
    $sourceUrl = 'https://github.com/strokedca/Stroked-Motorsport-demo.git'
    $privateRoot = Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    $identity = Join-Path $privateRoot 'recovery-key.txt'
    $work = Join-Path $privateRoot 'database'
    if (-not $BackupDestination) { $BackupDestination = Join-Path $env:USERPROFILE 'OneDrive\Stroked back up' }
    if (-not $SupabaseCliPath) { $SupabaseCliPath = Join-Path $env:USERPROFILE 'StrokedTools\supabase\supabase.exe' }
    $stage = $null
    $lock = $null
    $saved = $false
    $started = [DateTime]::UtcNow
    try {
        Write-Host '1/8 Checking the installed tools and previous database archive...'
        Assert-StrokedNonemptyFile $identity
        Assert-StrokedNonemptyFile $SupabaseCliPath
        Assert-StrokedNonemptyFile (Join-Path $BackupDestination 'Stroked-Recovery-Key.age')
        $previous = @(Get-ChildItem -LiteralPath $BackupDestination -File -Filter 'Stroked-database-*.zip.age' | Sort-Object LastWriteTimeUtc -Descending)
        if ($previous.Count -eq 0) { throw 'The verified database archive was not found in the OneDrive backup folder.' }
        $databaseArchive = $previous[0]
        $databaseHash = (Get-FileHash -LiteralPath $databaseArchive.FullName -Algorithm SHA256).Hash
        $age = (Get-Command age.exe -CommandType Application -ErrorAction Stop).Source
        $keygen = (Get-Command age-keygen.exe -CommandType Application -ErrorAction Stop).Source
        $git = (Get-Command git.exe -CommandType Application -ErrorAction Stop).Source
        try {
            $lock = [IO.File]::Open((Join-Path $privateRoot 'database-backup.lock'),
                [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch { throw 'Another backup may already be running, or its local lock cannot be opened.' }
        $cliVersion = (Invoke-StrokedNative $SupabaseCliPath @('--version') 'Supabase version check').Text.Trim()
        foreach ($command in @(@('db', 'query'), @('storage', 'cp'), @('config', 'pull'), @('functions', 'download'))) {
            $null = Invoke-StrokedNative $SupabaseCliPath ($command + @('--help')) 'Backup command help check'
        }
        $recipientText = (Invoke-StrokedNative $keygen @('-y', $identity) 'Public recovery recipient check').Text.Trim()
        $recipients = @($recipientText -split '\r?\n' | Where-Object { $_ -match '^age1[0-9a-z]{20,100}$' })
        if ($recipients.Count -ne 1) { throw 'The local recovery identity could not be validated.' }
        $recipient = $recipients[0]
        $runId = [Guid]::NewGuid().ToString('N')
        $stage = Join-Path $privateRoot ('files-run-' + $runId)
        New-StrokedPrivateDirectory $stage
        $payload = Join-Path $stage 'payload'
        $objectFolder = Join-Path $payload 'storage\files'
        $configFolder = Join-Path $payload 'supabase-reference'
        $null = New-Item -ItemType Directory -Path $objectFolder -Force
        $null = New-Item -ItemType Directory -Path $configFolder -Force
        $common = @(('--remote=' + $project), '--workdir', $work)
        $queryFile = Join-Path $stage 'inventory-query.sql'
        $sql = @'
SELECT 'STROKED_INVENTORY_V1:' || replace(encode(convert_to(jsonb_build_object(
  'formatVersion', 1,
  'projectRef', 'aodywiwkhtxwlscpqnda',
  'capturedUtc', clock_timestamp(),
  'cronAvailable', to_regclass('cron.job') IS NOT NULL,
  'buckets', COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM storage.buckets b), '[]'::jsonb),
  'objects', COALESCE((SELECT jsonb_agg(to_jsonb(o) - 'last_accessed_at' ORDER BY o.bucket_id, o.name) FROM storage.objects o), '[]'::jsonb),
  'extensions', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', e.extname, 'version', e.extversion, 'schema', n.nspname) ORDER BY e.extname) FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace), '[]'::jsonb),
  'publications', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.pubname) FROM pg_publication p), '[]'::jsonb),
  'publicationTables', COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.pubname, t.schemaname, t.tablename) FROM pg_publication_tables t), '[]'::jsonb)
)::text, 'UTF8'), 'base64'), E'\n', '') || ':END_STROKED_INVENTORY_V1' AS backup_inventory;
'@
        [IO.File]::WriteAllText($queryFile, $sql)
        $queryArguments = @('db', 'query') + $common + @('--file', $queryFile, '--read-only', '--output', 'json', '--agent=no')
        Write-Host '2/8 Reading the Storage inventory and bucket settings...'
        $beforeText = (Invoke-StrokedNative $SupabaseCliPath $queryArguments 'Storage inventory export').Text
        $before = ConvertFrom-StrokedInventoryOutput $beforeText
        [IO.File]::WriteAllText((Join-Path $payload 'storage\inventory-before.json'), ($before | ConvertTo-Json -Depth 50), (New-Object Text.UTF8Encoding($false)))
        $objectRecords = New-Object 'System.Collections.Generic.List[object]'
        $objectList = @($before.objects)
        $storageStarted = [DateTime]::UtcNow.ToString('o')
        Write-Host ('3/8 Downloading and checking ' + $objectList.Count + ' uploaded files...')
        for ($index = 0; $index -lt $objectList.Count; $index++) {
            $object = $objectList[$index]
            $url = Get-StrokedStorageUrl ([string]$object.bucket_id) ([string]$object.name)
            # Map untrusted remote keys to generated local names. Original keys
            # are preserved in the manifest, never used as filesystem paths.
            $localName = ('{0:D8}.bin' -f $index)
            $file = Join-Path $objectFolder $localName
            $second = Join-Path $stage ('check-' + $localName)
            $null = Invoke-StrokedNative $SupabaseCliPath (@('storage', 'cp', $url, $file, '--experimental') + $common) ('Storage file ' + ($index + 1) + ' download')
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'A Storage download did not create its local file.' }
            $bytes = (Get-Item -LiteralPath $file).Length
            if ($null -ne $object.metadata.size -and [long]$object.metadata.size -ne $bytes) { throw 'A downloaded Storage file did not match its recorded byte length.' }
            $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            $null = Invoke-StrokedNative $SupabaseCliPath (@('storage', 'cp', $url, $second, '--experimental') + $common) ('Storage file ' + ($index + 1) + ' verification download')
            if ((Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash -ne $hash) { throw 'Two downloads of a Storage object did not match. No new archive was marked saved.' }
            Remove-Item -LiteralPath $second -Force
            $objectRecords.Add([pscustomobject]@{
                bucket = [string]$object.bucket_id; key = [string]$object.name
                archivePath = ('storage/files/' + $localName); bytes = $bytes; sha256 = $hash
                remoteUpdatedAt = $object.updated_at; remoteMetadata = $object.metadata
            })
        }
        $storageFinished = [DateTime]::UtcNow.ToString('o')
        $afterText = (Invoke-StrokedNative $SupabaseCliPath $queryArguments 'Storage inventory recheck').Text
        $after = ConvertFrom-StrokedInventoryOutput $afterText
        Assert-StrokedStorageUnchanged $before $after
        [IO.File]::WriteAllText((Join-Path $payload 'storage\inventory-after.json'), ($after | ConvertTo-Json -Depth 50), (New-Object Text.UTF8Encoding($false)))

        Write-Host '4/8 Saving the Git source history and verifying the bundle...'
        $mirror = Join-Path $stage 'source-mirror.git'
        $bundle = Join-Path $payload 'Stroked-source.bundle'
        $sourceStarted = [DateTime]::UtcNow.ToString('o')
        $null = Invoke-StrokedNative $git @('-c', 'credential.helper=', '-c', 'credential.interactive=false', 'clone', '--mirror', $sourceUrl, $mirror) 'Git source mirror export'
        $sourceMain = (Invoke-StrokedNative $git @('-C', $mirror, 'rev-parse', 'refs/heads/main') 'Main source commit check').Text.Trim()
        if ($sourceMain -notmatch '^[0-9a-f]{40}$') { throw 'The main source commit could not be identified.' }
        $null = Invoke-StrokedNative $git @('-C', $mirror, 'bundle', 'create', $bundle, '--all') 'Git source bundle creation'
        Assert-StrokedNonemptyFile $bundle
        $null = Invoke-StrokedNative $git @('-C', $mirror, 'bundle', 'verify', $bundle) 'Git source bundle verification'
        $refs = (Invoke-StrokedNative $git @('bundle', 'list-heads', $bundle) 'Git source ref inventory').Text
        [IO.File]::WriteAllText((Join-Path $payload 'source-refs.txt'), $refs)
        $sourceFinished = [DateTime]::UtcNow.ToString('o')

        Write-Host '5/8 Saving deployed function code and Supabase configuration references...'
        $configWork = Join-Path $stage 'config-workspace'
        $null = New-Item -ItemType Directory -Path $configWork
        $null = Invoke-StrokedNative $SupabaseCliPath @('init', '--workdir', $configWork) 'Private configuration workspace setup'
        $configCommon = @(('--remote=' + $project), '--workdir', $configWork)
        $configResult = (Invoke-StrokedNative $SupabaseCliPath (@('config', 'pull') + $configCommon + @('--remote-label', 'hosted-record', '--force', '--yes', '--output-format', 'json')) 'Supabase configuration reference export').Text
        [IO.File]::WriteAllText((Join-Path $configFolder 'config-pull-report.txt'), $configResult)
        $config = Join-Path $configWork 'supabase\config.toml'
        Assert-StrokedNonemptyFile $config
        Copy-Item -LiteralPath $config -Destination (Join-Path $configFolder 'hosted-config.toml')
        $functionList = (Invoke-StrokedNative $SupabaseCliPath (@('functions', 'list') + $configCommon) 'Deployed function inventory').Text
        [IO.File]::WriteAllText((Join-Path $configFolder 'deployed-functions.txt'), $functionList)
        $null = Invoke-StrokedNative $SupabaseCliPath (@('functions', 'download', '--use-api') + $configCommon) 'Deployed function source export'
        $functionFolder = Join-Path $configWork 'supabase\functions'
        foreach ($requiredFunction in @('stroked-email-alerts', 'stroked-stripe-webhook')) {
            $functionFiles = @(Get-ChildItem -LiteralPath (Join-Path $functionFolder $requiredFunction) -File -Recurse -Force)
            if ($functionFiles.Count -eq 0) { throw 'A required deployed function source export was empty.' }
        }
        Copy-Item -LiteralPath $functionFolder -Destination (Join-Path $configFolder 'functions') -Recurse
        if ($before.cronAvailable) {
            $cronSql = "SELECT COALESCE(jsonb_agg(to_jsonb(j) ORDER BY j.jobid), '[]'::jsonb) AS cron_jobs FROM cron.job j;"
            $cronOutput = (Invoke-StrokedNative $SupabaseCliPath (@('db', 'query', $cronSql, '--read-only', '--output', 'json', '--agent=no') + $common) 'Cron configuration reference export').Text
            [IO.File]::WriteAllText((Join-Path $configFolder 'cron-jobs-reference.txt'), $cronOutput)
        }

        $providerStatus = [ordered]@{
            capturedUtc = [DateTime]::UtcNow.ToString('o')
            supabase = @{ projectRef = $project; config = 'supabase-reference/hosted-config.toml'; secrets = 'Masked provider credentials are not recoverable from config pull; preserve separately or rotate during recovery.' }
            cloudflare = @{ domain = 'stroked.ca'; status = 'Owner dashboard export still required for DNS and actual Pages/domain settings.'; sourceExpectedBuild = 'npm run build:production'; sourceExpectedOutput = 'dist'; actualHostedBuildVerified = $false }
            resend = @{ status = 'Owner dashboard inventory of sender domains and sending credentials still required.' }
            stripe = @{ status = 'Owner dashboard inventory of webhook destinations and signing credentials still required.' }
        }
        [IO.File]::WriteAllText((Join-Path $payload 'provider-inventory-status.json'), ($providerStatus | ConvertTo-Json -Depth 8))
        $notes = @'
STROKED FILES COMPONENT - RESTORE TEST PENDING

Pair this archive with the database archive named and hashed in manifest.json.
Their exports have separate times; they are not one simultaneous site snapshot.

Storage files have generated .bin names. manifest.json maps each file to its
original bucket, case-sensitive key, byte length and SHA-256. Recreate bucket
privacy/limits/policies, upload bytes to the ORIGINAL keys and content types,
then verify hashes. An empty bucket is recorded in the Storage inventories.

Stroked-source.bundle contains Git refs/history. Clone it into a new isolated
directory to recover the source, then build the recorded commit. The source
main commit is recorded; this is not proof of the live Cloudflare deploy SHA.
Deployed Edge Function source and listing are separately captured.

Supabase configuration was pulled into [remotes.hosted-record] in a private
workspace. Read the pull report for masked, skipped and unmanaged settings.
It is a configuration reference, not a complete secrets export. Reconfigure
provider secrets separately. Never blindly push this file into production.

The cron job reference is confidential and must remain encrypted. Never replay
real email/payment/webhook jobs into an active restore test environment.

Cloudflare DNS/Pages/domain, Resend sender and Stripe webhook dashboard exports,
an offsite download/decryption check and a full isolated restore remain pending.
No schedule or retention pruning is installed by this component.
'@
        [IO.File]::WriteAllText((Join-Path $payload 'RESTORE-NOTES.txt'), $notes)
        $files = @(Get-ChildItem -LiteralPath $payload -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName.Substring($payload.Length + 1).Replace('\', '/')
                bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
        $manifest = [ordered]@{
            formatVersion = 1; component = 'storage-source-supabase-reference'; projectRef = $project
            runId = $runId; startedUtc = $started.ToString('o'); packagedUtc = [DateTime]::UtcNow.ToString('o')
            supabaseCli = $cliVersion; recipient = $recipient; sourceRepository = $sourceUrl; sourceMainCommit = $sourceMain
            databaseArchive = @{ name = $databaseArchive.Name; bytes = $databaseArchive.Length; sha256 = $databaseHash }
            bucketCount = @($before.buckets).Count; storageObjectCount = $objectList.Count
            storageStartedUtc = $storageStarted; storageFinishedUtc = $storageFinished
            sourceStartedUtc = $sourceStarted; sourceFinishedUtc = $sourceFinished
            storageObjects = @($objectRecords.ToArray()); files = $files
            fullSiteBackup = $false; restoreTestPassed = $false; providerDashboardExportsComplete = $false
        }
        [IO.File]::WriteAllText((Join-Path $payload 'manifest.json'), ($manifest | ConvertTo-Json -Depth 50), (New-Object Text.UTF8Encoding($false)))
        Write-Host '6/8 Compressing and encrypting the files archive...'
        $zip = Join-Path $stage 'files.zip'
        $encrypted = Join-Path $stage 'files.zip.age'
        $verified = Join-Path $stage 'verification.zip'
        New-StrokedPayloadZip $payload $zip
        $null = Invoke-StrokedNative $age @('--encrypt', '-r', $recipient, '-o', $encrypted, $zip) 'Files archive encryption'
        Assert-StrokedNonemptyFile $encrypted
        Write-Host '7/8 Decrypting a test copy and comparing its checksum...'
        $null = Invoke-StrokedNative $age @('--decrypt', '-i', $identity, '-o', $verified, $encrypted) 'Files archive decryption verification'
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $verified -Algorithm SHA256).Hash) { throw 'The files archive decryption check did not match the original.' }
        Write-Host '8/8 Copying the verified encrypted files archive into OneDrive...'
        $name = 'Stroked-files-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ') + '-' + $runId + '.zip.age'
        $cipherHash = (Get-FileHash -LiteralPath $encrypted -Algorithm SHA256).Hash
        $destination = Publish-StrokedCiphertext $encrypted $BackupDestination $name $cipherHash
        $saved = $true
        try { Remove-Item -LiteralPath $stage -Recurse -Force }
        catch { Write-Host 'The private temporary workspace could not be removed; the encrypted copy was verified.' }
        Write-Host ''
        Write-Host 'FILES ARCHIVE VERIFIED AND SAVED' -ForegroundColor Green
        Write-Host $name
        Write-Host ('Uploaded files checked: ' + $objectList.Count + '; encrypted archive bytes: ' + (Get-Item -LiteralPath $destination).Length)
        Write-Host 'OneDrive upload, external provider exports and a full isolated restore still need checking.'
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if (-not $saved -and $stage) { Write-Host 'Files backup stopped. Earlier backups are retained, and this private local run is not marked saved.' }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not $HelperPath) { $HelperPath = Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1' }
        # The frozen database helper only defines its tested utilities when
        # dot-sourced. Distinct parameter names prevent binding collisions.
        . $HelperPath
        Invoke-StrokedFilesBackup -BackupDestination $BackupDestination -SupabaseCliPath $SupabaseCliPath
    }
    catch { Write-Host ('FILES BACKUP STOPPED: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
}
