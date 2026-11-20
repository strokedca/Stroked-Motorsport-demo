#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
foreach ($name in @('Stroked-Database-Backup.ps1','Stroked-Recovery-Check.ps1')) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw ($errors.Message -join "`n") }
}
. (Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1')
. (Join-Path $PSScriptRoot 'Stroked-Recovery-Check.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); $threw=$false; try{$null=& $Action}catch{$threw=$true}; Assert-True $threw $Message }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('stroked-recovery-test-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
    $source=Join-Path $temp 'payload'
    $null=New-Item -ItemType Directory -Path $source
    $names=@('roles.sql','schema.sql','data.sql','vault-root-key.txt','managed-schema-reference.sql','migration-history-schema.sql','migration-history-data.sql')
    foreach($name in $names){[IO.File]::WriteAllText((Join-Path $source $name),('synthetic fixture '+$name))}
    $fileInventory=@(Get-ChildItem -LiteralPath $source -File | ForEach-Object { [pscustomobject]@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
    $recipient='age1syntheticfixtureonly'
    $manifest=[ordered]@{formatVersion=1;projectRef='aodywiwkhtxwlscpqnda';component='database';recipient=$recipient;files=$fileInventory}
    [IO.File]::WriteAllText((Join-Path $source 'manifest.json'),($manifest|ConvertTo-Json -Depth 8))
    $dbZip=Join-Path $temp 'db.zip'
    # Match the actual first database export's Compress-Archive layout.
    Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $source -File|ForEach-Object{$_.FullName}) -DestinationPath $dbZip
    $checked=Test-StrokedArchiveManifest $dbZip 'database' $recipient
    Assert-True ($checked.CheckedFiles -eq $names.Count) 'Valid database manifest did not verify.'
    Assert-Throws {Test-StrokedArchiveManifest $dbZip 'database' 'wrong-recipient'} 'Wrong recovered identity was accepted.'
    [IO.File]::WriteAllText((Join-Path $source 'data.sql'),'changed synthetic data')
    $badZip=Join-Path $temp 'changed.zip'
    Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $source -File|ForEach-Object{$_.FullName}) -DestinationPath $badZip
    Assert-Throws {Test-StrokedArchiveManifest $badZip 'database' $recipient} 'Changed data passed a manifest check.'

    $outer=Join-Path $temp 'cloud.zip'
    $zip=[IO.Compression.ZipFile]::Open($outer,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach($name in @('Stroked-Recovery-Key.age','Stroked-database-20261120-132830Z-0123456789abcdef0123456789abcdef.zip.age','Stroked-files-20261120-144646Z-abcdef0123456789abcdef0123456789.zip.age')) {
            $entry=$zip.CreateEntry('Stroked back up/'+$name)
            $writer=New-Object IO.StreamWriter($entry.Open())
            try{$writer.Write('synthetic encrypted placeholder')}finally{$writer.Dispose()}
        }
    }finally{$zip.Dispose()}
    $zip=[IO.Compression.ZipFile]::OpenRead($outer)
    try {
        $set=Get-StrokedCloudSetEntries $zip
        Assert-True ($set.files.Count -eq 1 -and $set.database.Count -eq 1 -and $set.recovery.Count -eq 1) 'Cloud ZIP selection was not exact.'
        $copy=Join-Path $temp 'copied.age'
        Copy-StrokedZipEntry $set.recovery[0] $copy
        Assert-True ([IO.File]::ReadAllText($copy) -ceq 'synthetic encrypted placeholder') 'Cloud ZIP copy changed bytes.'
    }finally{$zip.Dispose()}
    $unsafe=Join-Path $temp 'unsafe.zip'
    $zip=[IO.Compression.ZipFile]::Open($unsafe,[IO.Compression.ZipArchiveMode]::Create)
    try{$null=$zip.CreateEntry('../escape.txt')}finally{$zip.Dispose()}
    $zip=[IO.Compression.ZipFile]::OpenRead($unsafe)
    try{Assert-Throws {Get-StrokedZipFileEntries $zip} 'Unsafe ZIP path was accepted.'}finally{$zip.Dispose()}

    $starter=Join-Path $PSScriptRoot 'RUN-RECOVERY-CHECK.cmd'
    $starterText=[IO.File]::ReadAllText($starter)
    foreach($name in @('Stroked-Database-Backup.ps1','Stroked-Recovery-Check.ps1')) {
        Assert-True ($starterText.ToLowerInvariant().Contains((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash.ToLowerInvariant())) 'Recovery starter checksum is stale.'
    }
    Write-Host 'Recovery checker tests passed (synthetic fixtures; no owner data or credentials).'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
exit 0
