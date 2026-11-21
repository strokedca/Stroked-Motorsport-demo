#Requires -Version 5.1
<#
Changes the passphrase wrapper around the SAME age identity. The password is
generated on the owner's Windows machine and goes only to its clipboard and
hidden age input. It is never printed, logged, passed as an argument or sent.
#>
[CmdletBinding()]
param([string]$RecoveryFolder = '')

function Publish-StrokedRecoveryKey {
    param([string]$NewCipher,[string]$LocalCipher,[string]$CloudCipher,[string]$PreviousFolder)
    Assert-StrokedNonemptyFile $NewCipher
    $hash=(Get-FileHash -LiteralPath $NewCipher -Algorithm SHA256).Hash
    $null=New-Item -ItemType Directory -Path $PreviousFolder -Force
    foreach($record in @(@($LocalCipher,'local-previous.age'),@($CloudCipher,'cloud-previous.age'))) {
        if(Test-Path -LiteralPath $record[0] -PathType Leaf){[IO.File]::Copy($record[0],(Join-Path $PreviousFolder $record[1]),$false)}
    }
    foreach($target in @($LocalCipher,$CloudCipher)) {
        $partial=$target+'.'+[Guid]::NewGuid().ToString('N')+'.partial'
        try {
            [IO.File]::Copy($NewCipher,$partial,$false)
            if((Get-FileHash -LiteralPath $partial).Hash -ne $hash){throw 'Recovery-key copy verification failed.'}
            if(Test-Path -LiteralPath $target -PathType Leaf){[IO.File]::Replace($partial,$target,[System.Management.Automation.Language.NullString]::Value)}
            else{[IO.File]::Move($partial,$target)}
            if((Get-FileHash -LiteralPath $target).Hash -ne $hash){throw 'Published recovery-key verification failed.'}
        }
        finally{if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue}}
    }
    return $hash
}

function Invoke-StrokedHiddenAgePrompt {
    param([string]$Program,[string[]]$Arguments)
    $prior=$ErrorActionPreference
    $global:LASTEXITCODE=-1
    try{$ErrorActionPreference='Continue'; & $Program @Arguments; $code=$global:LASTEXITCODE}
    finally{$ErrorActionPreference=$prior}
    if($code -ne 0){throw 'The hidden age passphrase step did not finish. This step has not updated the published key.'}
}

function Invoke-StrokedRecoveryPasswordUpdate {
    param([string]$RecoveryFolder = '')
    $ErrorActionPreference='Stop'
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root=Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    if(-not $RecoveryFolder){$RecoveryFolder=Join-Path $env:USERPROFILE 'OneDrive\Stroked back up'}
    $identity=Join-Path $root 'recovery-key.txt'
    $stage=Join-Path $root ('password-update-'+[Guid]::NewGuid().ToString('N'))
    $lock=$null
    $newPassword=$null
    try {
        Assert-StrokedNonemptyFile $identity
        Assert-StrokedNonemptyFile (Join-Path $RecoveryFolder 'Stroked-Recovery-Key.age')
        $lock=[IO.File]::Open((Join-Path $root 'database-backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        New-StrokedPrivateDirectory $stage
        $age=(Get-Command age.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
        $keygen=(Get-Command age-keygen.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
        $recipient=(Invoke-StrokedRecoveryNative $keygen @('-y',$identity) 'Existing public identity check').Text.Trim()
        Write-Host '1/4 Generating a new recovery password locally and copying it to the clipboard...'
        $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes=New-Object byte[] 24
        try{$rng.GetBytes($bytes);$newPassword=[Convert]::ToBase64String($bytes)}
        finally{$rng.Dispose();[Array]::Clear($bytes,0,$bytes.Length)}
        [Windows.Forms.Clipboard]::SetText($newPassword)
        $cipher=Join-Path $stage 'recovery-key-new.age'
        $recovered=Join-Path $stage 'recovery-key-test.txt'
        Write-Host '2/4 Protecting and testing the SAME recovery key with the new password...'
        Write-Host 'At each of the next THREE age prompts, press Ctrl+V and then Enter. The clipboard already holds the new password.'
        Write-Host 'The age input is hidden. Paste only at the age passphrase prompts.'
        Invoke-StrokedHiddenAgePrompt $age @('--passphrase','-o',$cipher,$identity)
        Invoke-StrokedHiddenAgePrompt $age @('--decrypt','-o',$recovered,$cipher)
        if((Get-FileHash -LiteralPath $identity).Hash -ne (Get-FileHash -LiteralPath $recovered).Hash){throw 'The newly protected identity did not match the original recovery key.'}
        foreach($component in @('database','files')) {
            $candidates=@(Get-ChildItem -LiteralPath $RecoveryFolder -File -Filter ("Stroked-$component-*.zip.age")|Sort-Object LastWriteTimeUtc -Descending)
            if($candidates.Count -eq 0){throw 'An archive was not found for the compatibility test.'}
            $plain=Join-Path $stage ($component+'.zip')
            $null=Invoke-StrokedRecoveryNative $age @('--decrypt','-i',$recovered,'-o',$plain,$candidates[0].FullName) 'Existing archive compatibility check'
            $expected='database'
            if($component -eq 'files'){$expected='storage-source-supabase-reference'}
            $null=Test-StrokedArchiveManifest $plain $expected $recipient
        }
        # Retain a verified encrypted next copy if saving the password succeeds
        # but a later publication fails. The original plaintext identity stays.
        $next=Join-Path $root 'recovery-key-protected-next.age'
        Copy-Item -LiteralPath $cipher -Destination $next -Force
        if((Get-FileHash -LiteralPath $next).Hash -ne (Get-FileHash -LiteralPath $cipher).Hash){throw 'The verified encrypted next copy did not match.'}
        Write-Host '3/4 Saving the new password in Edge Password Manager...'
        [Windows.Forms.Clipboard]::SetText($newPassword)
        $message="The new password is on your clipboard. In Edge Password Manager, edit the password for username backup-recovery at stroked.ca. Replace its password with Ctrl+V and SAVE it. Then hide the password with the eye button and CLOSE the password panel. Return here and click Yes only after saving it. Click No if you have not saved it yet."
        $answer=[Windows.Forms.MessageBox]::Show($message,'Save the new Stroked recovery password',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Information,[Windows.Forms.MessageBoxDefaultButton]::Button2)
        if($answer -ne [Windows.Forms.DialogResult]::Yes){throw 'Password-manager save was not confirmed. A verified encrypted next copy is retained privately; the cloud key was not updated.'}
        Write-Host '4/4 Updating the protected recovery-key copies and checking their hashes...'
        $previous=Join-Path $root ('previous-key-wrappers-'+[Guid]::NewGuid().ToString('N'))
        New-StrokedPrivateDirectory $previous
        $hash=Publish-StrokedRecoveryKey $next (Join-Path $root 'recovery-key-protected.age') (Join-Path $RecoveryFolder 'Stroked-Recovery-Key.age') $previous
        $report=[ordered]@{checkedUtc=[DateTime]::UtcNow.ToString('o');sameAgeIdentity=$true;existingArchiveCompatibilityPassed=$true;passwordManagerSaveConfirmedByOwner=$true;protectedKeyCopySha256=$hash;cloudFolderCopyVerified=$true;cloudUploadChecked=$false;oldCloudVersionsRemoved=$false;postgresRestoreDrillPassed=$false}
        [IO.File]::WriteAllText((Join-Path $root 'recovery-password-update-report.json'),($report|ConvertTo-Json))
        Write-Host ''
        Write-Host 'RECOVERY PASSWORD UPDATED AND KEY VERIFIED' -ForegroundColor Green
        Write-Host 'The existing database and files archives still work with the same underlying key.'
        Write-Host 'The updated encrypted key is in the OneDrive folder; cloud upload still needs checking.'
        Write-Host 'Earlier downloaded ZIPs and cloud history can still contain the previous password wrapper.'
        Write-Host 'Keep the Edge password panel closed when sharing the final result.'
    }
    finally {
        if($newPassword){try{if([Windows.Forms.Clipboard]::GetText() -ceq $newPassword){[Windows.Forms.Clipboard]::Clear()}}catch{};$newPassword=$null}
        if(Test-Path -LiteralPath $stage){try{Remove-Item -LiteralPath $stage -Recurse -Force}catch{Write-Host 'The private temporary password-update folder could not be fully removed.'}}
        if($null -ne $lock){$lock.Dispose()}
    }
}

if($MyInvocation.InvocationName -ne '.') {
    try {
        . (Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1')
        . (Join-Path $PSScriptRoot 'Stroked-Recovery-Check.ps1')
        Invoke-StrokedRecoveryPasswordUpdate -RecoveryFolder $RecoveryFolder
    }
    catch{Write-Host ('PASSWORD UPDATE STOPPED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
}
