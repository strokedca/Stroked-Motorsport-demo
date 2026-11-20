#Requires -Version 5.1
$ErrorActionPreference='Stop'
foreach($name in @('Stroked-Database-Backup.ps1','Stroked-Recovery-Check.ps1','Stroked-Update-Recovery-Password.ps1')) {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
    if($errors.Count -gt 0){throw ($errors.Message -join "`n")}
    . (Join-Path $PSScriptRoot $name)
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('stroked-password-test-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
    $new=Join-Path $temp 'new.age';$local=Join-Path $temp 'local.age';$cloud=Join-Path $temp 'cloud.age';$old=Join-Path $temp 'previous'
    [IO.File]::WriteAllText($new,'synthetic new ciphertext')
    [IO.File]::WriteAllText($local,'synthetic old local ciphertext')
    [IO.File]::WriteAllText($cloud,'synthetic old cloud ciphertext')
    $hash=Publish-StrokedRecoveryKey $new $local $cloud $old
    if((Get-FileHash -LiteralPath $local).Hash -ne $hash -or (Get-FileHash -LiteralPath $cloud).Hash -ne $hash){throw 'Published key-wrapper checksums differ.'}
    if([IO.File]::ReadAllText((Join-Path $old 'cloud-previous.age')) -cne 'synthetic old cloud ciphertext'){throw 'The previous encrypted wrapper was not retained for rollback.'}
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Stroked-Update-Recovery-Password.ps1'))
    if($source -match 'Write-Host\s+\$newPassword|WriteAllText\([^\r\n]*\$newPassword'){throw 'The new password must not be printed or written to a file.'}
    Write-Host 'Recovery-password updater checks passed (synthetic ciphertext only; no real passwords).'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
exit 0
