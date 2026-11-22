function Update-DrillCompletion($Report) {
    $b=$Report.BrowserChecks
    $images=([long]$Report.Checks.ImagesRestoredAndHashChecked -eq 0 -or [long]$b.RestoredImageLoadsObserved -gt 0)
    $Report.CoreWebsiteRecoveryVerified=[bool]($Report.Checks.ImportCommitted -and $Report.Checks.DatabaseProtectionChecksPassed -and $Report.Checks.PublicListingsAPICheckPassed -and
        $b.TestConfirmationCallbackObserved -and $b.TestRecoveryCallbackObserved -and $b.TestPasswordResetObserved -and $Report.Checks.TestPasswordLoginVerified -and
        $Report.Checks.SyntheticAccountsRemoved -and $b.RestoredAccountPasswordLoginObserved -and $b.RestoredAdministratorMFAVerified -and $b.AdministrationViewObserved -and $images)
    if($Report.Result -cne 'Stopped; review required'){
        if($Report.CoreWebsiteRecoveryVerified){$Report.Result='Recorded core website recovery checks passed'}
        elseif($Report.Checks.ImportCommitted){$Report.Result='Core data restored; browser checks incomplete'}
    }
    $Report.FullProviderRecoveryVerified=$false
    $Report.FullSiteRecoveryLimit='This proves the recorded local core-site checks only. Live email delivery, payment processing, provider account recovery and the scheduled 9AM backup are separate evidence.'
}
function Write-DrillSafeReport($Report,[string]$Path) {
    Update-DrillCompletion $Report
    $Report.UpdatedUTC=[DateTime]::UtcNow.ToString('o')
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Report|ConvertTo-Json -Depth 15))
    [IO.File]::WriteAllBytes($Path,$bytes)
    return ,$bytes
}
function Get-DrillCSP([string]$HTML) {
    $hashes=@(foreach($match in [regex]::Matches($HTML,'(?is)<script(?:\s[^>]*)?>(.*?)</script>')){
        if($match.Value -match '(?i)^<script[^>]*\bsrc='){continue}
        $sha=[Security.Cryptography.SHA256]::Create()
        try{"'sha256-"+[Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($match.Groups[1].Value)))+"'"}finally{$sha.Dispose()}
    }) -join ' '
    return "default-src 'self'; script-src 'self' "+$hashes+"; script-src-attr 'none'; style-src 'self' 'unsafe-inline'; connect-src 'self' http://127.0.0.1:54321 ws://127.0.0.1:54321; img-src 'self' data: blob: http://127.0.0.1:54321; font-src 'self' data:; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
}
function Stop-AllDrillContainers {
    foreach($row in @(Get-DrillContainers)){
        if($row.State.Running){$null=Invoke-LocalDocker @('stop','--time','15',$row.Name.TrimStart('/'))}
    }
    if(@(Get-DrillContainers | Where-Object {$_.State.Running}).Count){throw 'Some recovery services are still running.'}
}
function Start-DrillBrowserServer {
    param([string]$WebRoot,[string]$PackageRoot,$Report,[string]$ReportPath,$Keys,$Test,$RestoredIDs,$AdminIDs,$StoragePaths)
    if(-not ('StrokedLoopbackServer' -as [type])){Add-Type -Path (Join-Path $PackageRoot 'Loopback-Server.cs')}
    $nonce=[Guid]::NewGuid().ToString('N')
    $runtime=[ordered]@{nonce=$nonce;confirmID=$Test.ConfirmID;resetID=$Test.ResetID;testPassword=$Test.NewPassword}
    $runtimeBytes=[Text.Encoding]::UTF8.GetBytes('window.STROKED_DRILL=Object.freeze('+($runtime|ConvertTo-Json -Compress)+');')
    $server=New-Object StrokedLoopbackServer
    $stop=$false;$resetLink=$null;$confirmLink=$null
    $loaded=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    try {
        Write-Host ''
        Write-Host 'LOCAL WEBSITE RESTORED. Follow the recovery page in your browser.' -ForegroundColor Green
        Write-Host 'Address: http://127.0.0.1:3000/recovery-check.html'
        Write-Host 'Keep this window open. Download the report from that page when finished.'
        Start-Process 'http://127.0.0.1:3000/recovery-check.html'
        while(-not $stop){
            $request=$null
            try{$request=$server.Accept()}catch{continue}
            try {
                $path=$request.Target.Split('?')[0]
                if($request.Method -ceq 'POST'){
                    if(-not $request.Headers.ContainsKey('X-Stroked-Drill') -or $request.Headers['X-Stroked-Drill'] -cne $nonce -or
                       -not $request.Headers.ContainsKey('Origin') -or $request.Headers['Origin'] -cne 'http://127.0.0.1:3000'){
                        $request.Reply(403,'text/plain',[Text.Encoding]::UTF8.GetBytes('Local request refused.'),'','');continue
                    }
                    if($path -ceq '/__drill__/event'){
                        $event=[Text.Encoding]::UTF8.GetString($request.Body)|ConvertFrom-Json
                        $id=[string]$event.subject
                        $validID=($id -cmatch '^[a-f0-9-]{36}$')
                        switch -CaseSensitive ([string]$event.kind) {
                            'password_login' {if($validID -and $RestoredIDs.Contains($id)){$Report.BrowserChecks.RestoredAccountPasswordLoginObserved=$true}}
                            'mfa_verified' {if($validID -and $AdminIDs.Contains($id)){$Report.BrowserChecks.RestoredAdministratorMFAVerified=$true}}
                            'admin_view_opened' {$Report.BrowserChecks.AdministrationViewObserved=$true}
                            'confirmation_callback' {
                                if($id -ceq $Test.ConfirmID){
                                    $confirmed=(Invoke-DrillSQL ("BEGIN READ ONLY; SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE id='"+$id+"'::uuid; COMMIT;")).Trim()
                                    if($confirmed -ceq 't'){$Report.BrowserChecks.TestConfirmationCallbackObserved=$true}
                                }
                            }
                            'recovery_callback' {if($id -ceq $Test.ResetID){$Report.BrowserChecks.TestRecoveryCallbackObserved=$true}}
                            'password_updated' {if($id -ceq $Test.ResetID -and $event.recovery -eq $true){$Report.BrowserChecks.TestPasswordResetObserved=$true}}
                            'image_loaded' {
                                $objectPath=[Uri]::UnescapeDataString([string]$event.path)
                                $objectPath=[regex]::Replace($objectPath,'^/storage/v1/object/(?:public/|sign/|authenticated/)?','')
                                if($StoragePaths.Contains($objectPath)){$null=$loaded.Add($objectPath);$Report.BrowserChecks.RestoredImageLoadsObserved=$loaded.Count}
                            }
                        }
                        $null=Write-DrillSafeReport $Report $ReportPath
                        $request.Reply(200,'application/json',[Text.Encoding]::UTF8.GetBytes('{}'),'','');continue
                    }
                    if($path -ceq '/__drill__/begin-confirm'){
                        if($Report.Checks.SyntheticAccountsRemoved){throw 'Local disposable account checks already completed.'}
                        if(-not $confirmLink){$confirmLink=Read-DrillMailLink $Test $Test.ConfirmEmail 'signup'}
                        $request.Reply(200,'application/json',(ConvertTo-DrillJSONBytes @{url=$confirmLink}),'','');continue
                    }
                    if($path -ceq '/__drill__/begin-reset'){
                        $confirmed=(Invoke-DrillSQL ("BEGIN READ ONLY; SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE id='"+$Test.ConfirmID+"'::uuid; COMMIT;")).Trim()
                        if($confirmed -cne 't'){throw 'Confirmation has not completed in the local database.'}
                        if(-not $resetLink){
                            $r=Invoke-DrillHTTP 'http://127.0.0.1:54321/auth/v1/recover?redirect_to=http%3A%2F%2F127.0.0.1%3A3000%2F%3Fauth%3Drecovery' 'POST' @{apikey=$Keys.Anon} (ConvertTo-DrillJSONBytes @{email=$Test.ResetEmail})
                            $Report.Checks.LocalResetRequestHTTPStatus=$r.Status
                            if($r.Status -ne 200){throw 'Local reset email request did not succeed.'}
                            $resetLink=Read-DrillMailLink $Test $Test.ResetEmail 'recovery'
                        }
                        $request.Reply(200,'application/json',(ConvertTo-DrillJSONBytes @{url=$resetLink}),'','');continue
                    }
                    if($path -ceq '/__drill__/finish-account-checks'){
                        if(-not $Report.BrowserChecks.TestPasswordResetObserved){throw 'Restored password reset form has not completed.'}
                        $r=Invoke-DrillHTTP 'http://127.0.0.1:54321/auth/v1/token?grant_type=password' 'POST' @{apikey=$Keys.Anon} (ConvertTo-DrillJSONBytes @{email=$Test.ResetEmail;password=$Test.NewPassword})
                        if($r.Status -ne 200){throw 'Local reset password did not sign in successfully.'}
                        $signedIn=$r.Text | ConvertFrom-Json
                        if($signedIn.user.id -cne $Test.ResetID){throw 'Reset test signed in a different identity.'}
                        $Report.Checks.TestPasswordLoginVerified=$true
                        Remove-DrillTestUsers $Test $Keys
                        $Report.Checks.SyntheticAccountsRemoved=$true
                        $null=Write-DrillSafeReport $Report $ReportPath
                        $request.Reply(200,'application/json',[Text.Encoding]::UTF8.GetBytes('{}'),'','');continue
                    }
                    if($path -ceq '/__drill__/finish'){
                        try{
                            if(-not $Report.Checks.SyntheticAccountsRemoved){Remove-DrillTestUsers $Test $Keys;$Report.Checks.SyntheticAccountsRemoved=$true}
                            Stop-AllDrillContainers
                            $Report.Checks.LocalServicesStopped=$true
                            Update-DrillCompletion $Report
                            if($Report.CoreWebsiteRecoveryVerified){Remove-CompletedDrillClone;$Report.Checks.LocalCloneRemoved=$true;$Report.Checks.TemporaryFirewallRuleRemoved=$true}
                            else{$Report.Checks.LocalCloneKeptForIncompleteTest=$true}
                        }catch{$Report.Checks.LocalServicesStopped=$false;$Report.CleanupNeedsReview=$true}
                        $Report.FinishedUTC=[DateTime]::UtcNow.ToString('o')
                        $bytes=Write-DrillSafeReport $Report $ReportPath
                        $request.Reply(200,'application/json',$bytes,'','attachment; filename="Stroked-Website-Recovery-Report.json"')
                        $stop=$true;continue
                    }
                    $request.Reply(404,'text/plain',[Text.Encoding]::UTF8.GetBytes('Not found.'),'','');continue
                }
                if($request.Method -cne 'GET'){$request.Reply(400,'text/plain',[Text.Encoding]::UTF8.GetBytes('Unsupported method.'),'','');continue}
                if($path -cin @('/__drill__/status','/__drill__/report.json')){
                    $bytes=Write-DrillSafeReport $Report $ReportPath
                    $disposition='';if($path.EndsWith('.json')){$disposition='attachment; filename="Stroked-Website-Recovery-Report.json"'}
                    $request.Reply(200,'application/json',$bytes,'',$disposition);continue
                }
                if($path -ceq '/drill-runtime.js'){$request.Reply(200,'application/javascript',$runtimeBytes,'','');continue}
                $decoded=[Uri]::UnescapeDataString($path)
                if($decoded.Contains('\') -or $decoded.Contains(':') -or $decoded.Contains([char]0) -or $decoded -match '(^|/)\.(?:\.|)(/|$)'){throw 'Invalid local file path.'}
                if($decoded -ceq '/'){$decoded='/index.html'}
                $root=[IO.Path]::GetFullPath($WebRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
                $file=[IO.Path]::GetFullPath((Join-Path $WebRoot $decoded.TrimStart('/').Replace('/',[IO.Path]::DirectorySeparatorChar)))
                if(-not $file.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($file)){$request.Reply(404,'text/plain',[Text.Encoding]::UTF8.GetBytes('Not found.'),'','');continue}
                $extension=[IO.Path]::GetExtension($file).ToLowerInvariant()
                $types=@{'.html'='text/html; charset=utf-8';'.js'='application/javascript';'.css'='text/css';'.png'='image/png';'.jpg'='image/jpeg';'.jpeg'='image/jpeg';'.webp'='image/webp';'.gif'='image/gif';'.svg'='image/svg+xml';'.woff'='font/woff';'.woff2'='font/woff2';'.ico'='image/x-icon';'.txt'='text/plain'}
                if(-not $types.ContainsKey($extension)){$request.Reply(403,'text/plain',[Text.Encoding]::UTF8.GetBytes('Not served.'),'','');continue}
                $bytes=[IO.File]::ReadAllBytes($file);$csp=''
                if($extension -ceq '.html'){
                    $html=[Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n","`n").Replace("`r","`n")
                    $bytes=[Text.Encoding]::UTF8.GetBytes($html);$csp=Get-DrillCSP $html
                }
                $request.Reply(200,$types[$extension],$bytes,$csp,'')
            }catch{
                $Report.Checks.BrowserControllerLastError='A local browser check needs review; no raw private contents were recorded.'
                $null=Write-DrillSafeReport $Report $ReportPath
                try{$request.Reply(400,'application/json',(ConvertTo-DrillJSONBytes @{message='Local check stopped. Download the report for review.'}),'','')}catch{}
            }finally{$request.Dispose()}
        }
    }finally{$server.Dispose()}
}

function Remove-CompletedDrillClone {
    $rows=@(Get-DrillContainers)
    $volumes=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($row in $rows){
        if($row.State.Running){throw 'Clone cleanup requires all recovery containers stopped.'}
        foreach($mount in @($row.Mounts)){
            if($mount.Type -cne 'volume'){continue}
            if([string]$mount.Name -cnotmatch '^supabase_[a-z0-9_]+_StrokedRecoverySite$'){throw 'Unexpected volume name; clone cleanup needs review.'}
            $null=$volumes.Add([string]$mount.Name)
        }
    }
    # No force flags: Docker refuses to remove a running container or a volume used elsewhere.
    foreach($row in $rows){$null=Invoke-LocalDocker @('rm',$row.Name.TrimStart('/'))}
    foreach($name in $volumes){$null=Invoke-LocalDocker @('volume','rm',$name)}
    $net=@(ConvertFrom-DrillDockerArray -Text (Invoke-LocalDocker @('network','inspect','stroked-recovery-internal')))
    if($net.Count -ne 1 -or $net[0].Labels.'stroked.recovery' -cne 'StrokedRecoverySite'){throw 'Recovery network cleanup identity differs.'}
    $null=Invoke-LocalDocker @('network','rm','stroked-recovery-internal')
    Assert-ScopedFirewall
    Remove-NetFirewallRule -Name 'StrokedRecoverySite-BlockRemote' -ErrorAction Stop
}
