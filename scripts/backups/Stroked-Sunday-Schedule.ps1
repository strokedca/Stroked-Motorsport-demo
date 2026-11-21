#Requires -Version 5.1
<# Local Windows schedule. Uses the already verified fresh-backup helpers. #>
[CmdletBinding()]
param([ValidateSet('Install','Run','Status','Remove')][string]$ScheduleMode='Run')

function Get-StrokedWeeklyDue {
    param([DateTime]$LocalNow=[DateTime]::Now,[DateTime]$LastSuccessUtc=[DateTime]::MinValue,[TimeZoneInfo]$TimeZone=[TimeZoneInfo]::Local)
    $local=[DateTime]::SpecifyKind($LocalNow,[DateTimeKind]::Unspecified)
    $due=$local.Date.AddDays(-[int]$local.DayOfWeek).AddHours(9)
    if($local -lt $due){$due=$due.AddDays(-7)}
    $utc=[TimeZoneInfo]::ConvertTimeToUtc($due,$TimeZone)
    return [pscustomobject]@{DueLocal=$due;DueUtc=$utc;NextSundayLocal=$due.AddDays(7);NeedsBackup=($LastSuccessUtc -lt $utc)}
}

function Get-StrokedFreshSuccess {
    param([string]$Root,[string]$BackupFolder)
    $report=Join-Path $Root 'latest-fresh-backup-report.json'
    try {
        $r=[IO.File]::ReadAllText($report)|ConvertFrom-Json -ErrorAction Stop
        if($r.formatVersion -ne 1 -or $r.freshExports -isnot [bool] -or -not $r.freshExports -or $r.pairVerified -isnot [bool] -or -not $r.pairVerified){return [DateTime]::MinValue}
        $when=[DateTimeOffset]::MinValue
        if([string]$r.finishedUtc -notmatch '(Z|[+-]\d\d:\d\d)$' -or -not [DateTimeOffset]::TryParse([string]$r.finishedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$when)){return [DateTime]::MinValue}
        if($when.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)){return [DateTime]::MinValue}
        foreach($item in @(@('database',[string]$r.databaseArchive),@('files',[string]$r.filesArchive))) {
            if($item[1] -notmatch ('^Stroked-'+$item[0]+'-\d{8}-\d{6}Z-[0-9a-f]{32}\.zip\.age$')){return [DateTime]::MinValue}
            $file=Get-Item -LiteralPath (Join-Path $BackupFolder $item[1]) -ErrorAction Stop
            if($file.Length -lt 1){return [DateTime]::MinValue}
        }
        return $when.UtcDateTime
    } catch {return [DateTime]::MinValue}
}

function Get-StrokedScheduleSid {
    param([string]$Identity)
    if($Identity -match '^S-\d-\d+(?:-\d+)+$'){return $Identity}
    return (New-Object Security.Principal.NTAccount($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value
}

function New-StrokedSundayDefinition {
    param([string]$UserSid,[string]$ToolsFolder,[string]$ShellPath,[DateTime]$LocalNow=[DateTime]::Now,[bool]$Enabled=$true)
    $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
    $definition=$service.NewTask(0)
    $definition.RegistrationInfo.Author=$UserSid
    $definition.RegistrationInfo.Description='STROKED_SUNDAY_BACKUP_V1: Fresh encrypted backup Sunday 09:00 local time; lightweight hourly/sign-in checks catch up a missed weekly run. Requires the owner signed in and internet. Keeps existing archives.'
    $definition.Principal.Id='Owner'
    $definition.Principal.UserId=$UserSid
    $definition.Principal.LogonType=3 # Existing interactive token; no stored Windows password.
    $definition.Principal.RunLevel=0 # Least privilege, no administrator elevation.
    $due=Get-StrokedWeeklyDue -LocalNow $LocalNow
    $next=$due.NextSundayLocal
    $weekly=$definition.Triggers.Create(3)
    $weekly.Id='SundayMorning';$weekly.StartBoundary=$next.ToString('yyyy-MM-ddTHH:mm:ss')
    $weekly.DaysOfWeek=1;$weekly.WeeksInterval=1;$weekly.Enabled=$true
    $catchup=$definition.Triggers.Create(2)
    $catchup.Id='CatchUpCheck';$catchup.StartBoundary=$LocalNow.Date.AddHours(9).ToString('yyyy-MM-ddTHH:mm:ss')
    $catchup.DaysInterval=1;$catchup.Repetition.Interval='PT1H';$catchup.Repetition.Duration='P1D'
    $catchup.Repetition.StopAtDurationEnd=$false;$catchup.Enabled=$true
    $logon=$definition.Triggers.Create(9)
    $logon.Id='OwnerSignIn';$logon.UserId=$UserSid;$logon.Delay='PT2M';$logon.Enabled=$true
    $settings=$definition.Settings
    $settings.Enabled=$Enabled;$settings.AllowDemandStart=$true;$settings.Hidden=$false
    $settings.MultipleInstances=2;$settings.StartWhenAvailable=$true;$settings.RunOnlyIfNetworkAvailable=$true
    $settings.DisallowStartIfOnBatteries=$false;$settings.StopIfGoingOnBatteries=$false
    $settings.WakeToRun=$false;$settings.ExecutionTimeLimit='PT1H'
    $settings.RunOnlyIfIdle=$false
    $action=$definition.Actions.Create(0)
    $action.Path=$ShellPath
    $action.Arguments='-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "'+(Join-Path $ToolsFolder 'Stroked-Sunday-Schedule.ps1')+'" -ScheduleMode Run'
    $action.WorkingDirectory=$ToolsFolder
    return $definition
}

function Assert-StrokedSundayDefinition {
    param([string]$Xml,[string]$UserSid,[string]$ToolsFolder)
    $doc=[xml]$Xml
    $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
    $weekly=$doc.SelectSingleNode('//t:CalendarTrigger[t:ScheduleByWeek]',$ns)
    if($null -eq $weekly -or $weekly.StartBoundary -notmatch 'T09:00:00$' -or $null -eq $weekly.SelectSingleNode('t:ScheduleByWeek/t:DaysOfWeek/t:Sunday',$ns) -or $weekly.ScheduleByWeek.WeeksInterval -ne '1'){throw 'The Sunday 09:00 schedule did not verify.'}
    if((Get-StrokedScheduleSid $doc.SelectSingleNode('//t:Principal/t:UserId',$ns).InnerText) -cne $UserSid -or
       $doc.SelectSingleNode('//t:Principal/t:LogonType',$ns).InnerText -cne 'InteractiveToken' -or
       $doc.SelectSingleNode('//t:Principal/t:RunLevel',$ns).InnerText -cne 'LeastPrivilege'){throw 'The owner-only, password-free task identity did not verify.'}
    if($doc.SelectSingleNode('//t:Settings/t:StartWhenAvailable',$ns).InnerText -cne 'true' -or
       $doc.SelectSingleNode('//t:Settings/t:RunOnlyIfNetworkAvailable',$ns).InnerText -cne 'true' -or
       $doc.SelectSingleNode('//t:Settings/t:MultipleInstancesPolicy',$ns).InnerText -cne 'IgnoreNew'){throw 'Catch-up or overlap protection did not verify.'}
    if($doc.SelectSingleNode('//t:Exec/t:WorkingDirectory',$ns).InnerText -cne $ToolsFolder -or
       -not $doc.SelectSingleNode('//t:Exec/t:Arguments',$ns).InnerText.Contains('"'+(Join-Path $ToolsFolder 'Stroked-Sunday-Schedule.ps1')+'" -ScheduleMode Run')){throw 'The installed schedule helper path did not verify.'}
}

function Write-StrokedScheduleStatus {
    param([string]$Root,[string]$Status,[DateTime]$LastSuccessUtc,[string]$Detail='')
    $r=[ordered]@{formatVersion=1;checkedUtc=[DateTime]::UtcNow.ToString('o');status=$Status;lastVerifiedBackupUtc=$null;detail=$Detail;cloudUploadConfirmed=$false}
    if($LastSuccessUtc -ne [DateTime]::MinValue){$r.lastVerifiedBackupUtc=$LastSuccessUtc.ToString('o')}
    $target=Join-Path $Root 'scheduled-backup-status.json';$partial=$target+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($partial,($r|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        if(Test-Path -LiteralPath $target){[IO.File]::Replace($partial,$target,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($partial,$target)}
    } finally {if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}}
}

function Test-StrokedScheduleInternet {
    $response=$null
    try {
        $request=[Net.WebRequest]::Create('https://api.supabase.com/')
        $request.Method='HEAD';$request.Timeout=15000;$request.ReadWriteTimeout=15000;$request.AllowAutoRedirect=$false
        try {$response=$request.GetResponse()} catch [Net.WebException] {$response=$_.Exception.Response}
        if($null -eq $response){return $false}
        $code=[int]$response.StatusCode
        # An HTTP response (including an unauthenticated 4xx) proves transport
        # reachability. The authenticated backup commands check actual access.
        return ($code -ge 200 -and $code -lt 500)
    } catch {return $false} finally {if($null -ne $response){$response.Close()}}
}

function Start-StrokedScheduleDocker {
    param([string]$Docker)
    try {$os=(Invoke-StrokedRecoveryNative $Docker @('info','--format','{{.OSType}}') 'Docker readiness').Text.Trim()}
    catch {$os=''}
    if($os -eq 'linux'){return}
    if($os){throw 'The backup needs the Linux Docker engine.'}
    $null=Invoke-StrokedRecoveryNative $Docker @('desktop','start','--detach') 'Docker Desktop startup'
    for($i=0;$i -lt 60;$i++) {
        Start-Sleep -Seconds 2
        try {$os=(Invoke-StrokedRecoveryNative $Docker @('info','--format','{{.OSType}}') 'Docker startup readiness').Text.Trim()}catch{$os=''}
        if($os -eq 'linux'){return}
    }
    throw 'Docker Desktop did not become ready for this attempt.'
}

function Invoke-StrokedScheduledFreshProcess {
    param([string]$ToolsFolder,[string]$LogFolder)
    $process=New-Object Diagnostics.Process
    $process.StartInfo.FileName=Join-Path $PSHOME 'powershell.exe'
    $process.StartInfo.Arguments='-NoProfile -ExecutionPolicy RemoteSigned -File "'+(Join-Path $ToolsFolder 'Stroked-Run-Fresh-Backup.ps1')+'"'
    $process.StartInfo.WorkingDirectory=$ToolsFolder
    $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
    $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
    try {
        $null=$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(2700000)) {
            $null=Invoke-StrokedRecoveryNative (Join-Path $env:SystemRoot 'System32\taskkill.exe') @('/PID',[string]$process.Id,'/T','/F') 'Timed-out backup process cleanup'
            throw 'The backup exceeded its time limit.'
        }
        $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ')+'-'+[Guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText((Join-Path $LogFolder ($stamp+'-output.txt')),$stdout.GetAwaiter().GetResult(),(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $LogFolder ($stamp+'-errors.txt')),$stderr.GetAwaiter().GetResult(),(New-Object Text.UTF8Encoding($false)))
        if($process.ExitCode -ne 0){throw 'The fresh backup helper stopped. Its output is retained privately on this Surface.'}
    } finally {$process.Dispose()}
}

function Invoke-StrokedSundayBackup {
    $root=Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    $folder=Join-Path $env:USERPROFILE 'OneDrive\Stroked back up'
    $last=Get-StrokedFreshSuccess $root $folder
    $lock=$null
    try {
        $lock=[IO.File]::Open((Join-Path $root 'scheduled-backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $due=Get-StrokedWeeklyDue -LastSuccessUtc $last
        if(-not $due.NeedsBackup){Write-StrokedScheduleStatus $root 'NotDue' $last 'This Sunday period already has a verified fresh backup.';return}
        if(-not (Test-StrokedScheduleInternet)){Write-StrokedScheduleStatus $root 'WaitingForInternet' $last 'Waiting for internet; a later catch-up check will try again.';return}
        $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
        Write-StrokedScheduleStatus $root 'Starting' $last 'A weekly backup is due.'
        Start-StrokedScheduleDocker $docker
        $logs=Join-Path $root 'schedule-logs'
        if(-not (Test-Path -LiteralPath $logs)){New-StrokedPrivateDirectory $logs}
        $started=[DateTime]::UtcNow
        Invoke-StrokedScheduledFreshProcess $PSScriptRoot $logs
        $fresh=Get-StrokedFreshSuccess $root $folder
        if($fresh -lt $started.AddSeconds(-2)){throw 'This attempt did not produce a new verified backup-pair report.'}
        Write-StrokedScheduleStatus $root 'Success' $fresh 'Fresh encrypted pair verified locally. Let OneDrive finish uploading.'
    } catch {
        Write-StrokedScheduleStatus $root 'Failed' $last 'The last attempt stopped. Open Docker and use BACKUP-NOW, or review the private schedule logs.'
        throw
    } finally {if($null -ne $lock){$lock.Dispose()}}
}

function Install-StrokedSundaySchedule {
    $ErrorActionPreference='Stop'
    $root=Join-Path $env:LOCALAPPDATA 'StrokedBackup';$folder=Join-Path $env:USERPROFILE 'OneDrive\Stroked back up'
    $last=Get-StrokedFreshSuccess $root $folder
    if($last -eq [DateTime]::MinValue){throw 'A successful BACKUP-NOW report and both saved archives are required before scheduling.'}
    foreach($p in @((Join-Path $root 'recovery-key.txt'),(Join-Path $folder 'Stroked-Recovery-Key.age'),(Join-Path $env:USERPROFILE 'StrokedTools\supabase\supabase.exe'))){Assert-StrokedNonemptyFile $p}
    $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $null=Invoke-StrokedRecoveryNative $docker @('desktop','start','--help') 'Automatic Docker startup support check'
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$tasks=$service.GetFolder('\')
    $existing=$null;try{$existing=$tasks.GetTask('Stroked-Sunday-Backup')}catch{}
    if($null -ne $existing -and ($existing.Definition.RegistrationInfo.Description -notlike 'STROKED_SUNDAY_BACKUP_V1:*' -or (Get-StrokedScheduleSid $existing.Definition.Principal.UserId) -cne $sid)){throw 'A task with this name belongs to another owner or installer. It was not replaced.'}
    $definition=New-StrokedSundayDefinition $sid $PSScriptRoot (Join-Path $PSHOME 'powershell.exe')
    Assert-StrokedSundayDefinition $definition.XmlText $sid $PSScriptRoot
    # Task Scheduler interactive logon: no password, elevated account or remote
    # service is used. RegisterTaskDefinition returns only after local registration.
    $null=$tasks.RegisterTaskDefinition('Stroked-Sunday-Backup',$definition,6,$sid,$null,3,$null)
    $registered=$tasks.GetTask('Stroked-Sunday-Backup')
    Assert-StrokedSundayDefinition $registered.Definition.XmlText $sid $PSScriptRoot
    if(-not $registered.Enabled){throw 'The registered schedule is disabled.'}
    $next=(Get-StrokedWeeklyDue).NextSundayLocal.ToString('dddd, yyyy-MM-dd HH:mm')
    $r=[ordered]@{formatVersion=1;installedUtc=[DateTime]::UtcNow.ToString('o');taskName='Stroked-Sunday-Backup';weeklyDay='Sunday';weeklyLocalTime='09:00';timeZone=[TimeZoneInfo]::Local.Id;catchUpChecks='Hourly while available and after owner sign-in';interactiveOwnerOnly=$true;cloudUploadConfirmed=$false}
    [IO.File]::WriteAllText((Join-Path $root 'sunday-schedule-installation.json'),($r|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    Write-StrokedScheduleStatus $root 'Installed' $last 'Sunday 09:00 schedule registered and read back successfully.'
    Write-Host ''
    Write-Host 'SUNDAY BACKUP SCHEDULE INSTALLED' -ForegroundColor Green
    Write-Host 'Every Sunday at 9:00 AM, using this Surface local time.'
    Write-Host ('Next Sunday: '+$next)
    Write-Host 'Catch-up checks run after sign-in and hourly when available; a completed week is skipped.'
    Write-Host 'Keep the Surface awake, connected and signed in. Docker Desktop starts automatically when needed.'
    Write-Host 'Existing backup archives are kept. No archive retention deletion was installed.'
    Write-Host 'Use CHECK-BACKUP-STATUS.cmd to see the last verified backup and schedule status.'
}

function Show-StrokedSundayStatus {
    $root=Join-Path $env:LOCALAPPDATA 'StrokedBackup';$folder=Join-Path $env:USERPROFILE 'OneDrive\Stroked back up'
    $last=Get-StrokedFreshSuccess $root $folder
    $text='Sunday backup: 9:00 AM (Surface local time).'+"`r`n"
    $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
    try{$task=$service.GetFolder('\').GetTask('Stroked-Sunday-Backup');if($task.Enabled){$text+='Schedule: installed and enabled.'}else{$text+='Schedule: disabled.'}}catch{$text+='Schedule: not installed.'}
    if($last -ne [DateTime]::MinValue){$text+="`r`nLast verified fresh backup: "+$last.ToLocalTime().ToString('yyyy-MM-dd HH:mm')}else{$text+="`r`nNo valid fresh-backup pair report was found."}
    if((Get-StrokedWeeklyDue -LastSuccessUtc $last).NeedsBackup){$text+="`r`nA weekly backup is due; catch-up is waiting for an eligible run."}else{$text+="`r`nThis Sunday period already has a verified fresh backup."}
    try{$s=[IO.File]::ReadAllText((Join-Path $root 'scheduled-backup-status.json'))|ConvertFrom-Json;$text+="`r`nLast check: "+[string]$s.status+"`r`n"+[string]$s.detail}catch{}
    $text+="`r`n`r`nKeep the Surface awake, connected and signed in. Check OneDrive for completed uploads."
    Add-Type -AssemblyName System.Windows.Forms
    $null=[Windows.Forms.MessageBox]::Show($text,'Stroked backup status',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)
}

function Remove-StrokedSundaySchedule {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
    $task=$null;try{$task=$folder.GetTask('Stroked-Sunday-Backup')}catch{}
    if($null -eq $task){Write-Host 'The Stroked Sunday schedule is already absent.';return}
    if($task.Definition.RegistrationInfo.Description -notlike 'STROKED_SUNDAY_BACKUP_V1:*' -or (Get-StrokedScheduleSid $task.Definition.Principal.UserId) -cne $sid){throw 'This task was not identified as this owner Stroked schedule.'}
    $folder.DeleteTask('Stroked-Sunday-Backup',0)
    Write-Host 'Stroked Sunday schedule removed. Existing archives and recovery files are retained.'
}

. (Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1')
. (Join-Path $PSScriptRoot 'Stroked-Recovery-Check.ps1')
if($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference='Stop'
    try {
        switch($ScheduleMode){'Install'{Install-StrokedSundaySchedule};'Run'{Invoke-StrokedSundayBackup};'Status'{Show-StrokedSundayStatus};'Remove'{Remove-StrokedSundaySchedule}}
    } catch {Write-Host ('SCHEDULE STOPPED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
}
