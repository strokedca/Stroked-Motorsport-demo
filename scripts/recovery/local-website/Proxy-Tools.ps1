# The app services stay on the internal network. Only this fixed-target TCP
# proxy joins a normal bridge; it has no Docker socket or application secrets.
$script:DrillProxyImage='haproxy:3.2-alpine'
function Get-DrillProxy {
    param([switch]$AllowMissing)
    $name='stroked_recovery_loopback_StrokedRecoverySite'
    $id=(Invoke-LocalDocker @('ps','-aq','--filter',('name=^'+$name+'$'))).Trim()
    if(-not $id){if($AllowMissing){return $null};throw 'The local loopback proxy is absent.'}
    $rows=@(ConvertFrom-DrillDockerArray (Invoke-LocalDocker @('inspect',$id)))
    if($rows.Count -ne 1){throw 'Unexpected loopback proxy selection.'}
    $row=$rows[0]
    if($row.Name -cne ('/'+$name) -or $row.Config.Labels.'stroked.recovery' -cne 'StrokedRecoverySite' -or $row.Config.Labels.'stroked.recovery.component' -cne 'loopback-proxy' -or $row.Config.Image -cne $script:DrillProxyImage){throw 'Loopback proxy identity differs.'}
    if(-not $row.HostConfig.ReadonlyRootfs -or [string]$row.Config.User -cne '65534:65534' -or @($row.HostConfig.CapDrop).Count -ne 1 -or $row.HostConfig.CapDrop[0] -cne 'ALL' -or 'no-new-privileges:true' -cnotin @($row.HostConfig.SecurityOpt)){throw 'Loopback proxy runtime protections differ.'}
    $bindings=@{'8000/tcp'='54321';'5432/tcp'='54322';'8025/tcp'='54324';'3000/tcp'='54323'}
    if(@($row.HostConfig.PortBindings.PSObject.Properties).Count -ne 4){throw 'Loopback proxy published-port count differs.'}
    foreach($key in $bindings.Keys){$bound=@($row.HostConfig.PortBindings.$key);if($bound.Count -ne 1 -or $bound[0].HostIp -cne '127.0.0.1' -or $bound[0].HostPort -cne $bindings[$key]){throw 'Loopback proxy ports must be bound only to localhost.'}}
    if(@($row.Mounts).Count -ne 1 -or $row.Mounts[0].Destination -cne '/usr/local/etc/haproxy/haproxy.cfg' -or $row.Mounts[0].RW -or $row.Mounts[0].Type -cne 'bind'){throw 'Loopback proxy mount differs.'}
    return $row
}
function Ensure-DrillInternalNetwork {
    $name='stroked-recovery-internal'
    $found=(Invoke-LocalDocker @('network','ls','-q','--filter',('name=^'+$name+'$'))).Trim()
    if(-not $found){$null=Invoke-LocalDocker @('network','create','--driver','bridge','--internal','--label','stroked.recovery=StrokedRecoverySite',$name)}
    $rows=@(ConvertFrom-DrillDockerArray (Invoke-LocalDocker @('network','inspect',$name)))
    if($rows.Count -ne 1 -or -not $rows[0].Internal -or $rows[0].Driver -cne 'bridge' -or $rows[0].Labels.'stroked.recovery' -cne 'StrokedRecoverySite'){throw 'Recovery internal network identity differs.'}
}
function Ensure-DrillProxy {
    param([string]$RunFolder,[string]$PackageRoot)
    Ensure-DrillInternalNetwork
    $front='stroked-recovery-loopback'
    $found=(Invoke-LocalDocker @('network','ls','-q','--filter',('name=^'+$front+'$'))).Trim()
    if(-not $found){$null=Invoke-LocalDocker @('network','create','--driver','bridge','--label','stroked.recovery=StrokedRecoverySite','--label','stroked.recovery.component=loopback-proxy',$front)}
    $net=@(ConvertFrom-DrillDockerArray (Invoke-LocalDocker @('network','inspect',$front)))
    if($net.Count -ne 1 -or $net[0].Internal -or $net[0].Driver -cne 'bridge' -or $net[0].Labels.'stroked.recovery' -cne 'StrokedRecoverySite' -or $net[0].Labels.'stroked.recovery.component' -cne 'loopback-proxy'){throw 'Loopback frontend network identity differs.'}
    $target=Join-Path $RunFolder 'loopback-proxy.cfg'
    $bytes=[IO.File]::ReadAllBytes((Join-Path $PackageRoot 'loopback-proxy.cfg'))
    if(Test-Path -LiteralPath $target){if(((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -cne [Convert]::ToBase64String($bytes)){throw 'Existing loopback proxy configuration differs.'}}
    else{[IO.File]::WriteAllBytes($target,$bytes)}
    $row=Get-DrillProxy -AllowMissing
    foreach($entry in $net[0].Containers.PSObject.Properties){if(-not $row -or $entry.Name -cne $row.Id){throw 'An unrelated container is on the loopback frontend.'}}
    if(-not $row){
        $null=Invoke-LocalDocker @('pull',$script:DrillProxyImage)
        $null=Invoke-LocalDocker @('create','--name','stroked_recovery_loopback_StrokedRecoverySite','--label','stroked.recovery=StrokedRecoverySite','--label','stroked.recovery.component=loopback-proxy','--network',$front,'--read-only','--user','65534:65534','--cap-drop','ALL','--security-opt','no-new-privileges:true','--restart','no','--mount',('type=bind,source='+$target+',target=/usr/local/etc/haproxy/haproxy.cfg,readonly'),'-p','127.0.0.1:54321:8000','-p','127.0.0.1:54322:5432','-p','127.0.0.1:54323:3000','-p','127.0.0.1:54324:8025',$script:DrillProxyImage,'haproxy','-W','-db','-f','/usr/local/etc/haproxy/haproxy.cfg')
        $row=Get-DrillProxy
    }
    if($row.Mounts[0].Source.Replace('\','/') -cne $target.Replace('\','/')){throw 'Loopback proxy configuration path differs.'}
    foreach($name in @($row.NetworkSettings.Networks.PSObject.Properties.Name)){if($name -cnotin @($front,'stroked-recovery-internal')){throw 'Loopback proxy has an unexpected network.'}}
    if(-not $row.NetworkSettings.Networks.PSObject.Properties['stroked-recovery-internal']){$null=Invoke-LocalDocker @('network','connect','stroked-recovery-internal',$row.Name.TrimStart('/'))}
    if(-not $row.State.Running){$null=Invoke-LocalDocker @('start',$row.Name.TrimStart('/'))}
    $row=Get-DrillProxy
    if(-not $row.State.Running -or @($row.NetworkSettings.Networks.PSObject.Properties).Count -ne 2){throw 'Loopback proxy did not start on both expected networks.'}
}
function Stop-DrillProxy {
    $row=Get-DrillProxy -AllowMissing
    if($row -and $row.State.Running){$null=Invoke-LocalDocker @('stop','--time','15',$row.Name.TrimStart('/'))}
}
