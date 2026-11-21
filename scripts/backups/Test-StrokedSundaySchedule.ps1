#Requires -Version 5.1
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Stroked-Sunday-Schedule.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join "`n")}
. (Join-Path $PSScriptRoot 'Stroked-Sunday-Schedule.ps1')
function Assert-True {param([bool]$Condition,[string]$Message);if(-not $Condition){throw $Message}}
function Assert-Throws {param([scriptblock]$Action,[string]$Message);$threw=$false;try{$null=& $Action}catch{$threw=$true};Assert-True $threw $Message}
$zone=[TimeZoneInfo]::FindSystemTimeZoneById('Atlantic Standard Time')
$last=[DateTime]::Parse('2026-11-20T17:30:50Z').ToUniversalTime()
$before=Get-StrokedWeeklyDue ([DateTime]'2026-11-22T08:59:59') $last $zone
$at=Get-StrokedWeeklyDue ([DateTime]'2026-11-22T09:00:00') $last $zone
Assert-True (-not $before.NeedsBackup -and $at.NeedsBackup) 'The weekly gate did not open exactly Sunday at 09:00 local time.'
$missed=Get-StrokedWeeklyDue ([DateTime]'2026-11-24T14:00:00') $last $zone
Assert-True $missed.NeedsBackup 'A missed Sunday was silently skipped.'
$done=Get-StrokedWeeklyDue ([DateTime]'2026-11-24T14:00:00') ([DateTime]::Parse('2026-11-23T13:00:00Z').ToUniversalTime()) $zone
Assert-True (-not $done.NeedsBackup) 'Catch-up would duplicate an already completed week.'
$dst=Get-StrokedWeeklyDue ([DateTime]'2026-11-01T09:00:00') ([DateTime]::MinValue) $zone
$earlier=Get-StrokedWeeklyDue ([DateTime]'2026-10-25T09:00:00') ([DateTime]::MinValue) $zone
Assert-True (($dst.DueUtc-$earlier.DueUtc).TotalHours -eq 169) 'The Sunday schedule drifted across daylight-saving time.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ("stroked schedule's & fixture-"+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$taskName='Stroked-schedule-test-'+[Guid]::NewGuid().ToString('N')
$taskFolder=$null;$registered=$false
try {
 $backups=Join-Path $temp 'backups';$logs=Join-Path $temp 'logs'
 $null=New-Item -ItemType Directory -Path $backups,$logs
 $db='Stroked-database-20261120-173021Z-0123456789abcdef0123456789abcdef.zip.age'
 $files='Stroked-files-20261120-173050Z-abcdef0123456789abcdef0123456789.zip.age'
 foreach($n in @($db,$files)){[IO.File]::WriteAllText((Join-Path $backups $n),'synthetic ciphertext')}
 $r=@{formatVersion=1;freshExports=$true;pairVerified=$true;finishedUtc=[DateTime]::UtcNow.AddMinutes(-1).ToString('o');databaseArchive=$db;filesArchive=$files}
 $report=Join-Path $temp 'latest-fresh-backup-report.json'
 [IO.File]::WriteAllText($report,($r|ConvertTo-Json))
 Assert-True ((Get-StrokedFreshSuccess $temp $backups) -ne [DateTime]::MinValue) 'A valid verified-pair report was not recognized.'
 $r.pairVerified=$false;[IO.File]::WriteAllText($report,($r|ConvertTo-Json))
 Assert-True ((Get-StrokedFreshSuccess $temp $backups) -eq [DateTime]::MinValue) 'An unverified pair suppressed a due backup.'
 $r.pairVerified=$true;$r.databaseArchive='..\outside.age';[IO.File]::WriteAllText($report,($r|ConvertTo-Json))
 Assert-True ((Get-StrokedFreshSuccess $temp $backups) -eq [DateTime]::MinValue) 'An unsafe archive path was accepted.'
 Write-StrokedScheduleStatus $temp 'Installed' $last 'synthetic first state'
 Write-StrokedScheduleStatus $temp 'NotDue' $last 'synthetic replacement state'
 $status=[IO.File]::ReadAllText((Join-Path $temp 'scheduled-backup-status.json'))|ConvertFrom-Json
 Assert-True ($status.status -ceq 'NotDue') 'Status replacement failed on Windows PowerShell 5.1.'

 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $definition=New-StrokedSundayDefinition $sid $temp (Join-Path $PSHOME 'powershell.exe') ([DateTime]'2026-11-20T13:00:00') $false
 Assert-StrokedSundayDefinition $definition.XmlText $sid $temp
 Assert-True (-not $definition.Settings.Enabled) 'The CI-only task must remain disabled.'
 $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$taskFolder=$service.GetFolder('\')
 $null=$taskFolder.RegisterTaskDefinition($taskName,$definition,2,$sid,$null,3,$null)
 $registered=$true
 $readback=$taskFolder.GetTask($taskName)
 Assert-StrokedSundayDefinition $readback.Definition.XmlText $sid $temp
 Assert-True (-not $readback.Enabled) 'The registered CI task was unexpectedly enabled.'
 $taskFolder.DeleteTask($taskName,0);$registered=$false

 $fake=Join-Path $temp 'Stroked-Run-Fresh-Backup.ps1'
 [IO.File]::WriteAllText($fake,"Write-Output 'synthetic background helper'; exit 0")
 Invoke-StrokedScheduledFreshProcess $temp $logs
 Assert-True ((@(Get-ChildItem -LiteralPath $logs -File -Filter '*-output.txt').Count) -eq 1) 'Background output was not kept locally.'
 [IO.File]::WriteAllText($fake,"Write-Output 'synthetic failing helper'; exit 3")
 Assert-Throws {Invoke-StrokedScheduledFreshProcess $temp $logs} 'A failed child process was marked successful.'
 $starter=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SETUP-SUNDAY-BACKUP.cmd')).ToLowerInvariant()
 foreach($name in @('Stroked-Database-Backup.ps1','Stroked-Recovery-Check.ps1','Stroked-Files-Backup.ps1','Stroked-Run-Fresh-Backup.ps1','Stroked-Sunday-Schedule.ps1')) {
  Assert-True ($starter.Contains((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash.ToLowerInvariant())) 'Schedule starter checksum is stale.'
 }
 Write-Host 'Sunday schedule tests passed: weekly/DST gates, missed-run catch-up, native disabled-task registration/readback/removal, status replacement and background child success/failure. Synthetic data only.'
} finally {
 if($registered -and $null -ne $taskFolder){$taskFolder.DeleteTask($taskName,0)}
 Remove-Item -LiteralPath $temp -Recurse -Force
}
exit 0
