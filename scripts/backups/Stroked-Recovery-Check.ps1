#Requires -Version 5.1
<#
Checks a downloaded OneDrive set using only its password-protected identity.
No live database, Storage, provider API, deployment or schedule is touched.
This is an offsite download/decryption/content/source check, not a PostgreSQL
restore drill. Secret plaintext is confined to a private temporary directory.
#>
[CmdletBinding()]
param([string]$CloudZipPath = '', [string]$UtilityHelperPath = '')

function Get-StrokedZipFileEntries {
    param($Archive)
    $entries = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    foreach ($entry in $Archive.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ($name.StartsWith('/') -or $name.Contains(':') -or $name -match '(^|/)\.\.(/|$)') { throw 'An archive contains an unsafe path.' }
        if ($name.EndsWith('/')) { continue }
        if ($entries.ContainsKey($name)) { throw 'An archive contains a duplicate file path.' }
        $entries.Add($name, $entry)
    }
    return $entries
}

function Get-StrokedCloudSetEntries {
    param($Archive)
    $entries = Get-StrokedZipFileEntries $Archive
    $sets = @{ recovery = @(); database = @(); files = @() }
    foreach ($name in $entries.Keys) {
        $base = ($name -split '/')[-1]
        if ($base -ceq 'Stroked-Recovery-Key.age') { $sets.recovery += $entries[$name] }
        elseif ($base -match '^Stroked-database-\d{8}-\d{6}Z-[0-9a-f]{32}\.zip\.age$') { $sets.database += $entries[$name] }
        elseif ($base -match '^Stroked-files-\d{8}-\d{6}Z-[0-9a-f]{32}\.zip\.age$') { $sets.files += $entries[$name] }
    }
    if ($sets.recovery.Count -ne 1 -or $sets.database.Count -ne 1 -or $sets.files.Count -ne 1) {
        throw 'Choose the ZIP downloaded from OneDrive containing one recovery-key file, one database archive and one files archive.'
    }
    return $sets
}

function Copy-StrokedZipEntry {
    param($Entry, [string]$Destination)
    if ($Entry.Length -lt 1 -or $Entry.Length -gt 2147483648) { throw 'An input backup file has an unsupported size for this first recovery check.' }
    $source = $Entry.Open()
    try {
        $target = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $source.CopyTo($target) }
        finally { $target.Dispose() }
    }
    finally { $source.Dispose() }
}

function Get-StrokedZipEntryHash {
    param($Entry)
    $stream = $Entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Test-StrokedArchiveManifest {
    param([string]$ZipPath, [string]$ExpectedComponent, [string]$Recipient)
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = Get-StrokedZipFileEntries $archive
        if (-not $entries.ContainsKey('manifest.json') -or $entries['manifest.json'].Length -gt 8388608) { throw 'The archive manifest is missing or too large.' }
        $reader = New-Object IO.StreamReader($entries['manifest.json'].Open(), [Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        try { $manifest = $text | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'An archive manifest is not valid JSON.' }
        if ($manifest.formatVersion -ne 1 -or $manifest.projectRef -cne 'aodywiwkhtxwlscpqnda' -or
            $manifest.component -cne $ExpectedComponent -or $manifest.recipient -cne $Recipient) {
            throw 'An archive does not match the Stroked project, component or recovered identity.'
        }
        $verified = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach ($file in @($manifest.files)) {
            $path = [string]$file.path
            if (-not $path) { $path = [string]$file.name }
            if (-not $path -or $path -ceq 'manifest.json' -or $verified.ContainsKey($path) -or -not $entries.ContainsKey($path)) { throw 'A manifest file is missing or duplicated.' }
            $entry = $entries[$path]
            if ([string]$file.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [long]$file.bytes -ne $entry.Length -or
                (Get-StrokedZipEntryHash $entry) -ne [string]$file.sha256) { throw 'An archive file failed its byte-length or checksum check.' }
            $verified.Add($path, $file)
        }
        if ($verified.Count -lt 1 -or $entries.Count -ne $verified.Count + 1) { throw 'The archive has missing or unlisted files.' }
        if ($ExpectedComponent -ceq 'database') {
            foreach ($required in @('roles.sql','schema.sql','data.sql','vault-root-key.txt','managed-schema-reference.sql','migration-history-schema.sql','migration-history-data.sql')) {
                if (-not $verified.ContainsKey($required)) { throw 'The database archive is missing a required recovery component.' }
            }
        }
        else {
            if (-not $verified.ContainsKey('Stroked-source.bundle')) { throw 'The files archive is missing its Git source bundle.' }
            $objects = @($manifest.storageObjects)
            if ($objects.Count -ne [long]$manifest.storageObjectCount) { throw 'The image restore inventory count is inconsistent.' }
            $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            $objectPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($object in $objects) {
                $path = [string]$object.archivePath
                $key = [string]$object.bucket + [char]0 + [string]$object.key
                if (-not $keys.Add($key) -or -not $objectPaths.Add($path) -or -not $verified.ContainsKey($path)) { throw 'An image restore mapping is missing or duplicated.' }
                $record = $verified[$path]
                if ([long]$record.bytes -ne [long]$object.bytes -or [string]$record.sha256 -ne [string]$object.sha256) { throw 'An image restore mapping failed its checksum check.' }
            }
        }
        return [pscustomobject]@{ Manifest = $manifest; CheckedFiles = $verified.Count }
    }
    finally { $archive.Dispose() }
}

function Invoke-StrokedRecoveryNative {
    param([string]$Program, [string[]]$Arguments, [string]$Step)
    $prior = $ErrorActionPreference
    $global:LASTEXITCODE = -1
    try { $ErrorActionPreference = 'Continue'; $captured = @(& $Program @Arguments 2>&1); $code = $global:LASTEXITCODE }
    finally { $ErrorActionPreference = $prior }
    if ($code -ne 0) { throw "$Step did not pass (exit $code). Captured contents have not been displayed." }
    return [pscustomobject]@{ Text = (($captured | ForEach-Object { [string]$_ }) -join "`n") }
}

function Find-StrokedCloudZip {
    param([string]$GivenPath)
    if ($GivenPath) { return $GivenPath }
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $candidates = @(Get-ChildItem -LiteralPath $downloads -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)OneDrive|Stroked[ _-]?back' } | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($candidate in $candidates) {
        $archive = $null
        try { $archive = [IO.Compression.ZipFile]::OpenRead($candidate.FullName); $null = Get-StrokedCloudSetEntries $archive; return $candidate.FullName }
        catch { }
        finally { if ($null -ne $archive) { $archive.Dispose() } }
    }
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object Windows.Forms.OpenFileDialog
    try {
        $picker.Title = 'Choose the ZIP downloaded from OneDrive containing your three encrypted backup files'
        $picker.Filter = 'Downloaded OneDrive ZIP (*.zip)|*.zip'
        $picker.InitialDirectory = $downloads
        if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Recovery check cancelled before any decryption.' }
        return $picker.FileName
    }
    finally { $picker.Dispose() }
}

function Invoke-StrokedRecoveryCheck {
    param([string]$CloudZipPath = '')
    $ErrorActionPreference = 'Stop'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $privateRoot = Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    $null = New-Item -ItemType Directory -Path $privateRoot -Force
    $stage = Join-Path $privateRoot ('recovery-check-' + [Guid]::NewGuid().ToString('N'))
    $lock = $null
    $passed = $false
    $report = $null
    try {
        $lock = [IO.File]::Open((Join-Path $privateRoot 'database-backup.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        New-StrokedPrivateDirectory $stage
        $age = (Get-Command age.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $keygen = (Get-Command age-keygen.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $git = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        Write-Host '1/5 Finding the ZIP downloaded from OneDrive...'
        $inputZip = Find-StrokedCloudZip $CloudZipPath
        Write-Host ('Using downloaded ZIP: ' + [IO.Path]::GetFileName($inputZip))
        $inputArchive = [IO.Compression.ZipFile]::OpenRead($inputZip)
        $inputs = @{}
        $inputNames = @{}
        try {
            $set = Get-StrokedCloudSetEntries $inputArchive
            foreach ($component in @('recovery','database','files')) {
                $entry = $set[$component][0]
                $name = ($entry.FullName.Replace('\','/') -split '/')[-1]
                $path = Join-Path $stage $name
                Copy-StrokedZipEntry $entry $path
                $inputs[$component] = $path; $inputNames[$component] = $name
            }
        }
        finally { $inputArchive.Dispose() }
        $identity = Join-Path $stage 'downloaded-recovered-identity.txt'
        Write-Host '2/5 Unlocking the DOWNLOADED recovery identity with your saved password...'
        Write-Host 'Use the backup-recovery password saved for stroked.ca in Edge Password Manager.'
        Write-Host 'At the age passphrase prompt, paste that password and press Enter. Typing is hidden.'
        $unlocked = $false
        for ($attempt = 1; $attempt -le 3 -and -not $unlocked; $attempt++) {
            if (Test-Path -LiteralPath $identity) { Remove-Item -LiteralPath $identity -Force }
            $prior = $ErrorActionPreference
            $global:LASTEXITCODE = -1
            try { $ErrorActionPreference = 'Continue'; & $age --decrypt -o $identity $inputs.recovery; $code = $global:LASTEXITCODE }
            finally { $ErrorActionPreference = $prior }
            $unlocked = ($code -eq 0 -and (Test-Path -LiteralPath $identity -PathType Leaf))
            if (-not $unlocked -and $attempt -lt 3) { Write-Host 'The unlock did not finish. Copy the saved recovery password and try again at the passphrase prompt.' }
        }
        if (-not $unlocked) { throw 'The downloaded recovery identity could not be unlocked.' }
        $recipient = (Invoke-StrokedRecoveryNative $keygen @('-y', $identity) 'Recovered public recipient check').Text.Trim()
        if ($recipient -notmatch '^age1[0-9a-z]{20,100}$') { throw 'The downloaded recovery identity was not valid.' }
        Write-Host '3/5 Decrypting both downloaded archives and checking every manifest file...'
        $dbZip = Join-Path $stage 'downloaded-database.zip'
        $filesZip = Join-Path $stage 'downloaded-files.zip'
        $null = Invoke-StrokedRecoveryNative $age @('--decrypt','-i',$identity,'-o',$dbZip,$inputs.database) 'Downloaded database decryption'
        $null = Invoke-StrokedRecoveryNative $age @('--decrypt','-i',$identity,'-o',$filesZip,$inputs.files) 'Downloaded files decryption'
        $db = Test-StrokedArchiveManifest $dbZip 'database' $recipient
        $files = Test-StrokedArchiveManifest $filesZip 'storage-source-supabase-reference' $recipient
        $pair = $files.Manifest.databaseArchive
        if ($pair.name -cne $inputNames.database -or [long]$pair.bytes -ne (Get-Item -LiteralPath $inputs.database).Length -or
            [string]$pair.sha256 -ne (Get-FileHash -LiteralPath $inputs.database -Algorithm SHA256).Hash) { throw 'The downloaded database archive does not match the files archive recovery pair.' }
        Write-Host '4/5 Restoring the downloaded Git bundle into an isolated local repository...'
        $bundle = Join-Path $stage 'downloaded-source.bundle'
        $sourceArchive = [IO.Compression.ZipFile]::OpenRead($filesZip)
        try { Copy-StrokedZipEntry ($sourceArchive.GetEntry('Stroked-source.bundle')) $bundle }
        finally { $sourceArchive.Dispose() }
        $restored = Join-Path $stage 'restored-source.git'
        $null = Invoke-StrokedRecoveryNative $git @('clone','--bare',$bundle,$restored) 'Downloaded source bundle restore'
        $main = (Invoke-StrokedRecoveryNative $git @('-C',$restored,'rev-parse','refs/heads/main') 'Restored source commit check').Text.Trim()
        if ($main -cne [string]$files.Manifest.sourceMainCommit) { throw 'The restored source commit did not match the backup manifest.' }
        $report = [ordered]@{
            formatVersion = 1; checkedUtc = [DateTime]::UtcNow.ToString('o'); projectRef = 'aodywiwkhtxwlscpqnda'
            inputZipName = [IO.Path]::GetFileName($inputZip); downloadedRecoveryIdentityUnlocked = $true
            originalLocalIdentityUsed = $false; databaseArchive = $inputNames.database; filesArchive = $inputNames.files
            databaseManifestFilesChecked = $db.CheckedFiles; filesManifestFilesChecked = $files.CheckedFiles
            storageObjectsChecked = $files.Manifest.storageObjectCount; sourceMainCommit = $main; sourceBundleRestorePassed = $true
            downloadDecryptionContentCheckPassed = $true; postgresRestoreDrillPassed = $false
            fullSiteRecoveryVerified = $false; schedulingInstalled = $false
        }
        Write-Host '5/5 Removing this check''s temporary decrypted files...'
        Remove-Item -LiteralPath $stage -Recurse -Force
        $stage = $null
        $reportPath = Join-Path $privateRoot ('recovery-check-report-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ') + '.json')
        [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8))
        $passed = $true
        Write-Host ''
        Write-Host 'DOWNLOAD RECOVERY CHECK PASSED' -ForegroundColor Green
        Write-Host ('Images checked: ' + $files.Manifest.storageObjectCount + '; source bundle restored and verified.')
        Write-Host 'The downloaded encrypted identity unlocked both cloud-downloaded archives.'
        Write-Host 'A full PostgreSQL/site restore drill, provider exports and regular backup setup remain pending.'
        Write-Host ('Safe check report saved locally: ' + $reportPath)
    }
    finally {
        if ($stage -and (Test-Path -LiteralPath $stage)) {
            try { Remove-Item -LiteralPath $stage -Recurse -Force }
            catch { Write-Host ('Temporary decrypted files could not be removed from the private folder: ' + $stage) }
        }
        if ($null -ne $lock) { $lock.Dispose() }
        if (-not $passed) { Write-Host 'The download recovery check did not pass. The original encrypted backup files are retained.' }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not $UtilityHelperPath) { $UtilityHelperPath = Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1' }
        . $UtilityHelperPath
        Invoke-StrokedRecoveryCheck -CloudZipPath $CloudZipPath
    }
    catch { Write-Host ('RECOVERY CHECK STOPPED: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
}
