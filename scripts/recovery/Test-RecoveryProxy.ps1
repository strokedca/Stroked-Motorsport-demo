[CmdletBinding()]
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Local-Core.ps1')
. (Join-Path $Package 'Proxy-Tools.ps1')
function Invoke-LocalDocker([string[]]$Arguments,[int]$TimeoutSeconds=30){$r=@(& docker @Arguments 2>&1);if($LASTEXITCODE -ne 0){throw ('Fixture Docker failed: '+($Arguments[0..([Math]::Min(1,$Arguments.Count-1))] -join ' ')+': '+($r -join "`n"))};return ($r -join "`n")}
function Invoke-QuietNative([string]$Program,[string[]]$Arguments,[int]$TimeoutSeconds=30){
    # Only the endpoint/native runner changes for Linux; the restart helper,
    # stop/start arguments, proxy, volume guard and CLI are the shipped code.
    $r=@(& $Program @Arguments 2>&1);$code=$LASTEXITCODE
    if($script:NativePrivateLogPrefix){[IO.File]::WriteAllText($script:NativePrivateLogPrefix+'-fixture.txt',($r -join "`n"))}
    if($code -ne 0){throw ('Actual fixture CLI failed during '+$Arguments[0])}
    return ($r -join "`n")
}
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('stroked-proxy-ci-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$work=Join-Path $root 'work';$null=New-Item -ItemType Directory -Path $work
$cli=Join-Path $root 'supabase'
$api='supabase_kong_StrokedRecoverySite'
try{
    $null=Invoke-LocalDocker @('pull','busybox:1.37.0')
    Ensure-DrillInternalNetwork
    # Reproduce the architectural failure with a real listening service.
    $null=Invoke-LocalDocker @('run','-d','--name',$api,'--label','com.supabase.cli.project=StrokedRecoverySite','--network','stroked-recovery-internal','-p','127.0.0.1:54321:8000','busybox:1.37.0','sh','-c','mkdir -p /www; echo proxy-fixture >/www/index.html; exec httpd -f -p 8000 -h /www')
    Start-Sleep -Seconds 1
    $failed=$false;try{$null=Invoke-WebRequest 'http://127.0.0.1:54321/' -TimeoutSec 3}catch{$failed=$true}
    Assert-True $failed 'Internal-only port publication unexpectedly succeeded; expected reproduction missing.'
    Write-Host 'REPRODUCED: internal-only container listens but its requested host port is unavailable.'
    Ensure-DrillProxy $root $Package
    $response=Invoke-WebRequest 'http://127.0.0.1:54321/' -TimeoutSec 10
    Assert-True ($response.StatusCode -eq 200 -and $response.Content.Trim() -ceq 'proxy-fixture') 'Proxy did not forward the real HTTP response.'
    $digest=(Invoke-LocalDocker @('image','inspect',$script:DrillProxyImage,'--format','{{index .RepoDigests 0}}')).Trim()
    Write-Host ('TESTED_PROXY_DIGEST='+$digest)
    $null=Invoke-LocalDocker @('stop','--timeout','5',$api);$null=Invoke-LocalDocker @('rm',$api)
    # Exact CLI release used on the Surface; checksum from official release.
    $archive=Join-Path $root 'supabase.tar.gz'
    Invoke-WebRequest 'https://github.com/supabase/cli/releases/download/v3.2.0/supabase_linux_amd64.tar.gz' -OutFile $archive
    Assert-True ((Get-FileHash $archive -Algorithm SHA256).Hash -ieq 'fb88b175a817563505be02c60872060bcb8d5c869a1aa5656eaeb085d4a2f1e4') 'CLI release checksum differs.'
    & tar -xzf $archive -C $root
    if($LASTEXITCODE -ne 0){throw 'CLI extraction failed.'}
    & $cli init --workdir $work *> (Join-Path $root 'init.log')
    if($LASTEXITCODE -ne 0){throw 'Fixture CLI init failed.'}
    $config=Join-Path $work 'supabase/config.toml'
    $text=[IO.File]::ReadAllText($config)
    $text=[regex]::Replace($text,'(?m)^project_id\s*=.*$','project_id = "StrokedRecoverySite"')
    $text=Enable-DrillTOTPConfig $text
    [IO.File]::WriteAllText($config,$text)
    & $cli start --workdir $work --network-id stroked-recovery-internal --exclude logflare,vector,edge-runtime,supavisor,imgproxy *> (Join-Path $root 'start.log')
    if($LASTEXITCODE -ne 0){
        # Synthetic CI project contains no private owner data or credentials.
        Get-Content (Join-Path $root 'start.log') -Tail 80|Where-Object {$_ -notmatch '(?i)key|token|secret|postgresql://'}|Write-Host
        throw 'Actual CLI3.2.0 cold start through loopback proxy failed.'
    }
    foreach($url in @('http://127.0.0.1:54321/auth/v1/health','http://127.0.0.1:54324/api/v1/messages')){$r=Invoke-WebRequest $url -TimeoutSec 10;Assert-True ($r.StatusCode -eq 200) 'Real Auth/Mail API unreachable through proxy.'}
    $db=Get-DrillContainer 'supabase_db_StrokedRecoverySite' -RequireRunning
    $auth=Get-ContainerValues (Get-DrillContainer 'supabase_auth_StrokedRecoverySite' -RequireRunning)
    Assert-True ($auth['GOTRUE_MFA_TOTP_VERIFY_ENABLED'] -ceq 'true') 'Actual Auth TOTP verification setting is not enabled.'
    foreach($row in @(Get-DrillContainers)){Assert-True (@($row.NetworkSettings.Networks.PSObject.Properties.Name).Count -eq 1 -and $row.NetworkSettings.Networks.PSObject.Properties.Name -ceq 'stroked-recovery-internal') 'A real app container has an external network.'}
    $oldID=$db.Id
    Invoke-DrillStackRestart $cli $work $root $Package
    $db=Get-DrillContainer 'supabase_db_StrokedRecoverySite' -RequireRunning
    Assert-True ($db.Id -cne $oldID) 'CLI restart did not exercise container replacement.'
    foreach($url in @('http://127.0.0.1:54321/auth/v1/health','http://127.0.0.1:54324/api/v1/messages')){$r=Invoke-WebRequest $url -TimeoutSec 10;Assert-True ($r.StatusCode -eq 200) 'Real API not ready after shipped restart helper.'}
    $auth=Get-ContainerValues (Get-DrillContainer 'supabase_auth_StrokedRecoverySite' -RequireRunning)
    Assert-True ($auth['GOTRUE_MFA_TOTP_VERIFY_ENABLED'] -ceq 'true') 'TOTP setting was lost on actual CLI restart.'
    Stop-DrillProxy
    Write-Host 'PASS: real proxy, localhost-only bindings, actual SupabaseCLI3.2.0 cold start plus shipped guarded volume-preserving restart/container replacement, PostgreSQL readiness, TOTP verification enabled and Auth/Mail HTTP through proxy; app containers internal-only.'
}finally{
    $names=(Invoke-LocalDocker @('ps','-aq','--filter','label=com.supabase.cli.project=StrokedRecoverySite')).Trim()
    foreach($id in @($names -split '\s+'|Where-Object {$_})) {try{$null=Invoke-LocalDocker @('stop','--timeout','5',$id);$null=Invoke-LocalDocker @('rm',$id)}catch{}}
    try{Stop-DrillProxy;$null=Invoke-LocalDocker @('rm','stroked_recovery_loopback_StrokedRecoverySite')}catch{}
    foreach($name in @('stroked-recovery-loopback','stroked-recovery-internal')){try{$null=Invoke-LocalDocker @('network','rm',$name)}catch{}}
}
