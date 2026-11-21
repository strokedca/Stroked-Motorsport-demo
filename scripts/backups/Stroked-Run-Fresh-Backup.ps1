#Requires -Version 5.1
[CmdletBinding()]
param([string]$FreshBackupFolder='')

function Invoke-StrokedFreshBackup {
    param([string]$FreshBackupFolder='')
    $ErrorActionPreference='Stop'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if(-not $FreshBackupFolder){$FreshBackupFolder=Join-Path $env:USERPROFILE 'OneDrive\Stroked back up'}
    $root=Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    $stage=Join-Path $root ('fresh-check-'+[Guid]::NewGuid().ToString('N'))
    $lock=$null
    try {
        $lock=[IO.File]::Open((Join-Path $root 'fresh-backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        New-StrokedPrivateDirectory $stage
        $prior=@(Get-ChildItem -LiteralPath $FreshBackupFolder -File | ForEach-Object {$_.Name})
        $shell=Join-Path $PSHOME 'powershell.exe'
        Write-Host 'Making a FRESH database export, followed by current images and source...'
        # Deliberately no UseExistingExports switch. Each component fails closed.
        & $shell -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1') -DestinationFolder $FreshBackupFolder
        if($global:LASTEXITCODE -ne 0){throw 'Fresh database export stopped. Earlier backups are retained.'}
        $newDb=@(Get-ChildItem -LiteralPath $FreshBackupFolder -File -Filter 'Stroked-database-*.zip.age' | Where-Object {$_.Name -notin $prior})
        if($newDb.Count -ne 1){throw 'The fresh database archive could not be identified unambiguously.'}
        & $shell -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Stroked-Files-Backup.ps1') -BackupDestination $FreshBackupFolder
        if($global:LASTEXITCODE -ne 0){throw 'The files component stopped. This run is not a complete backup pair.'}
        $newFiles=@(Get-ChildItem -LiteralPath $FreshBackupFolder -File -Filter 'Stroked-files-*.zip.age' | Where-Object {$_.Name -notin $prior})
        if($newFiles.Count -ne 1){throw 'The fresh files archive could not be identified unambiguously.'}
        $identity=Join-Path $root 'recovery-key.txt'
        $age=(Get-Command age.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $keygen=(Get-Command age-keygen.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $recipient=(Invoke-StrokedRecoveryNative $keygen @('-y',$identity) 'Recipient check').Text.Trim()
        foreach($component in @(@('database',$newDb[0]),@('storage-source-supabase-reference',$newFiles[0]))) {
            $zip=Join-Path $stage ($component[0]+'.zip')
            $null=Invoke-StrokedRecoveryNative $age @('--decrypt','-i',$identity,'-o',$zip,$component[1].FullName) 'Fresh archive verification'
            $checked=Test-StrokedArchiveManifest $zip $component[0] $recipient
            if($component[0] -eq 'database') {
                if($checked.Manifest.reusedExistingExports){throw 'The database component reused historical SQL.'}
            } else {
                $pair=$checked.Manifest.databaseArchive
                if($pair.name -cne $newDb[0].Name -or [long]$pair.bytes -ne $newDb[0].Length -or $pair.sha256 -ne (Get-FileHash -LiteralPath $newDb[0].FullName).Hash){throw 'The files archive does not pair with this fresh database export.'}
            }
        }
        $report=[ordered]@{formatVersion=1;finishedUtc=[DateTime]::UtcNow.ToString('o');freshExports=$true;databaseArchive=$newDb[0].Name;filesArchive=$newFiles[0].Name;pairVerified=$true;cloudUploadConfirmed=$false;fullSiteRestorePassed=$false}
        [IO.File]::WriteAllText((Join-Path $root 'latest-fresh-backup-report.json'),($report|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        Write-Host ''
        Write-Host 'FRESH BACKUP PAIR VERIFIED AND SAVED' -ForegroundColor Green
        Write-Host $newDb[0].Name
        Write-Host $newFiles[0].Name
        Write-Host 'Let OneDrive finish uploading. Keep earlier backups; no retention or schedule was installed.'
    }
    finally {
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
        if($null -ne $lock){$lock.Dispose()}
    }
}
. (Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1')
. (Join-Path $PSScriptRoot 'Stroked-Recovery-Check.ps1')
if($MyInvocation.InvocationName -ne '.') {
    try {Invoke-StrokedFreshBackup -FreshBackupFolder $FreshBackupFolder}
    catch {Write-Host ('FRESH BACKUP STOPPED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
}
