#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ZipPath,[switch]$RequireWindows51)
$ErrorActionPreference='Stop'
if($RequireWindows51 -and ($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1)){throw 'Actual Windows PowerShell 5.1 is required.'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('stroked-packaged-ci-'+[guid]::NewGuid().ToString('N'))
try{
    $null=New-Item -ItemType Directory -Path $root
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $root
    $package=Join-Path $root 'Stroked-Local-Website-Restore-v1.9'
    $entry=Join-Path $package 'Restore-Local-Website.ps1'
    if(-not (Test-Path -LiteralPath $entry -PathType Leaf)){throw 'Versioned package root is missing.'}
    foreach($file in @(Get-ChildItem -LiteralPath $package -Filter '*.ps1')){
        $bytes=[IO.File]::ReadAllBytes($file.FullName)
        if($bytes.Length -lt 6 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191){throw ('UTF-8 marker missing: '+$file.Name)}
        if($bytes[3] -eq 239 -and $bytes[4] -eq 187 -and $bytes[5] -eq 191){throw ('Duplicate UTF-8 marker: '+$file.Name)}
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ('Delivered script does not parse: '+$file.Name+'; '+$errors[0].Message)}
    }
    if($RequireWindows51){
        $broken=Join-Path $root 'duplicate-marker.ps1'
        [byte[]]$old=@(239,187,191)+[IO.File]::ReadAllBytes($entry)
        [IO.File]::WriteAllBytes($broken,$old)
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($broken,[ref]$tokens,[ref]$errors)
        if(-not $errors.Count -or @($errors|Where-Object {$_.ErrorId -ceq 'UnexpectedAttribute'}).Count -eq 0){throw 'Owner duplicate-marker parser failure did not reproduce.'}
        Write-Host 'REPRODUCED: duplicate encoding marker prevents CmdletBinding/param from parsing on Windows PowerShell 5.1.'
    }
    $argsForDocker=@{Package=$package;RequireWindows51=$RequireWindows51}
    & (Join-Path $PSScriptRoot 'Test-RecoveryDocker.ps1') @argsForDocker
    & (Join-Path $PSScriptRoot 'Test-RecoveryStartup.ps1') -Package $package
    & (Join-Path $PSScriptRoot 'Test-RecoveryTableACLPlan.ps1') -Package $package
    & (Join-Path $PSScriptRoot 'Test-RecoveryRoutineACLPlan.ps1') -Package $package
    Write-Host ('PACKAGE_SHA256='+(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant())
    Write-Host ('PACKAGE_BYTES='+(Get-Item -LiteralPath $ZipPath).Length)
    Write-Host ('PASS: extracted ZIP scripts parse and pass shipped-helper regressions on PowerShell '+$PSVersionTable.PSVersion)
}finally{
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
