[CmdletBinding()]
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Local-Core.ps1')
. (Join-Path $Package 'Browser-Controller.ps1')
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Invoke-LocalDocker([string[]]$Arguments){
    # Same shipped inspection/isolation/cleanup code; only the runner endpoint
    # changes to this disposable Linux CI daemon instead of a Windows pipe.
    $result=@(& docker @Arguments 2>&1);$code=$LASTEXITCODE
    if($code -ne 0){throw ('Fixture Docker command failed: '+($Arguments[0..([Math]::Min(1,$Arguments.Count-1))] -join ' ')+': '+($result -join "`n"))}
    return ($result -join "`n")
}
$suffixes=@('studio','pg_meta','edge_runtime','storage','rest','realtime','inbucket','auth','kong','vector','analytics','db')
$owned=New-Object 'Collections.Generic.List[string]'
$old='stroked-recovery-fixture-bridge'
$internal='stroked-recovery-internal'
try{
    Assert-True (-not (Invoke-LocalDocker @('ps','-aq','--filter','label=com.supabase.cli.project=StrokedRecoverySite')).Trim()) 'CI daemon already contains the scoped project.'
    Assert-True (-not (Invoke-LocalDocker @('network','ls','-q','--filter',('name=^'+$internal+'$'))).Trim()) 'CI internal network already exists.'
    $null=Invoke-LocalDocker @('pull','busybox:1.37.0')
    $null=Invoke-LocalDocker @('network','create','--driver','bridge',$old)
    foreach($suffix in $suffixes){
        $name='supabase_'+$suffix+'_StrokedRecoverySite'
        $run=@('run','-d','--name',$name,'--label','com.supabase.cli.project=StrokedRecoverySite','--network',$old,'--network-alias',('fixture-'+$suffix))
        if($suffix -ceq 'studio'){$run+=@('-p','127.0.0.1::8080')}
        $null=Invoke-LocalDocker ($run+@('busybox:1.37.0','sh','-c','trap "exit 0" TERM INT; while :; do sleep 1; done'))
        $owned.Add($name)
    }
    $containers=@(Get-DrillContainers)
    Assert-True ($containers.Count -eq 12) 'Expected twelve real Docker fixture containers.'
    $db=Get-DrillContainer 'supabase_db_StrokedRecoverySite' -RequireRunning
    Assert-True ($db.Id -cmatch '^[a-f0-9]{64}$') 'Database fixture ID is not scalar.'
    Set-DrillIsolation $containers
    Assert-DrillIsolation
    foreach($row in @(Get-DrillContainers)){
        $suffix=$row.Name -creplace '^/supabase_','' -creplace '_StrokedRecoverySite$',''
        Assert-True (('fixture-'+$suffix) -cin $row.NetworkSettings.Networks.'stroked-recovery-internal'.Aliases) 'Real Docker alias was lost.'
    }
    Set-DrillIsolation @(Get-DrillContainers)
    Stop-AllDrillContainers
    Assert-True (@(Get-DrillContainers|Where-Object {$_.State.Running}).Count -eq 0) 'Real Docker cleanup failed.'
    # Check resume with the services stopped, then restart one scalar service.
    Set-DrillIsolation @(Get-DrillContainers)
    $null=Invoke-LocalDocker @('start','supabase_db_StrokedRecoverySite')
    $null=Get-DrillContainer 'supabase_db_StrokedRecoverySite' -RequireRunning
    Assert-DrillIsolation
    Stop-AllDrillContainers
    Write-Host 'PASS: real Docker twelve-container connect/disconnect, aliases, internal network, individually scoped stop and stopped-container resume.'
}finally{
    # This hosted CI daemon has only disposable fixture containers; no volumes,
    # production services, owner credentials or owner archives are involved.
    foreach($name in $owned){try{$null=Invoke-LocalDocker @('stop','--timeout','5',$name);$null=Invoke-LocalDocker @('rm',$name)}catch{Write-Warning ('Fixture cleanup failed for '+$name)}}
    foreach($network in @($internal,$old)){try{$null=Invoke-LocalDocker @('network','rm',$network)}catch{Write-Warning 'Fixture network cleanup needs review.'}}
}
