#Requires -Version 5.1
# Owner-run local restore. No hosted credentials, production commands or paid services.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$package=$PSScriptRoot
foreach($file in @('Local-Core.ps1','Schema-Parser.ps1','Archive-Reader.ps1','Import-Plan.ps1','Protected-Table-ACL.ps1','Website-Tools.ps1','Browser-Controller.ps1','Proxy-Tools.ps1')){. (Join-Path $package $file)}
$project='StrokedRecoverySite'
$root=Join-Path $env:LOCALAPPDATA 'StrokedBackup'
$work=Join-Path $env:LOCALAPPDATA $project
$cli=Join-Path $env:USERPROFILE 'StrokedTools\supabase\supabase.exe'
$statePath=Join-Path $root 'website-recovery-state.json'
$reportPath=Join-Path $package ('Stroked-Website-Restore-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'.json')
$drillLock=$null;$lock=$null;$stage=$null;$keys=$null;$mutated=$false;$script:ActiveTestState=$null;$script:LastSQLState=$null;$script:LastDataExportIssue=$null;$script:LastNativeFailure=$null
$phase='Starting';$state=@{};$resumedStartup=$false;$proxyTouched=$false;$script:StartupPhase=$null;$script:NativePrivateLogPrefix=$null
$report=[ordered]@{
    ReportType='Stroked isolated website recovery';Version='1.8';StartedUTC=[DateTime]::UtcNow.ToString('o')
    LiveProjectContacted=$false;RealEmailDeliveryEnabled=$false;PaymentsEnabled=$false
    CoreWebsiteRecoveryVerified=$false;FullProviderRecoveryVerified=$false;Result='In progress'
    Checks=[ordered]@{}
    BrowserChecks=[ordered]@{TestConfirmationCallbackObserved=$false;TestRecoveryCallbackObserved=$false;TestPasswordResetObserved=$false;RestoredAccountPasswordLoginObserved=$false;RestoredAdministratorMFAVerified=$false;AdministrationViewObserved=$false;RestoredImageLoadsObserved=0}
}
function Save-DrillCheckpoint {
    $state.UpdatedUTC=[DateTime]::UtcNow.ToString('o')
    $temporary=$statePath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temporary,($state|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
        if(Test-Path -LiteralPath $statePath){[IO.File]::Replace($temporary,$statePath,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$statePath)}
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
try {
    Write-Host 'Stroked local website restore v1.8'
    Write-Host '1/7 Checking the existing local recovery setup...'
    $phase='Checking administrator launch';Assert-DrillAdministrator
    $report.Checks.AdministratorLaunchConfirmed=$true
    $phase='Checking existing recovery folders'
    if(-not (Test-Path -LiteralPath $root -PathType Container) -or -not (Test-Path -LiteralPath $work -PathType Container)){throw 'Existing local recovery folders are missing.'}
    if(((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'The private backup root is a link; review required.'}
    $phase='Checking local browser port 3000'
    $probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,3000)
    try{$probe.Start(1)}finally{$probe.Stop()}
    $phase='Acquiring local website recovery lock'
    $drillLock=[IO.File]::Open((Join-Path $root 'website-recovery.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $phase='Acquiring existing backup lock'
    $lock=[IO.File]::Open((Join-Path $root 'database-backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $phase='Finding existing Docker executable';$script:docker=Resolve-DrillLocalTool 'docker.exe'
    $phase='Finding existing age executable';$age=Resolve-DrillLocalTool 'age.exe'
    $phase='Finding existing age-keygen executable';$keygen=Resolve-DrillLocalTool 'age-keygen.exe'
    $phase='Finding existing Git executable';$git=Resolve-DrillLocalTool 'git.exe'
    $phase='Checking existing local CLI'
    if(-not (Test-Path -LiteralPath $cli -PathType Leaf)){throw 'Existing local Supabase CLI is missing.'}
    $phase='Checking local recovery configuration'
    foreach($path in @($work,(Join-Path $work 'supabase'),(Join-Path $work 'supabase\config.toml'))){if(((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'A recovery config path is a link; review required.'}}
    $configText=[IO.File]::ReadAllText((Join-Path $work 'supabase\config.toml'))
    if([regex]::Matches($configText,'(?m)^project_id\s*=\s*"StrokedRecoverySite"\s*(?:#[^\r\n]*)?\r?$').Count -ne 1){throw 'Recovery configuration project_id differs.'}
    $phase='Checking scoped Windows firewall';Assert-ScopedFirewall
    $phase='Checking local recovery checkpoint'
    if(Test-Path -LiteralPath $statePath){
        $saved=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
        foreach($p in $saved.PSObject.Properties){$state[$p.Name]=$p.Value}
        if($state.Project -cne $project -or [string]$state.ContainerID -cnotmatch '^[a-f0-9]{64}$' -or [string]$state.RunID -cnotmatch '^[a-f0-9]{32}$'){throw 'Recovery checkpoint does not match this local container.'}
        $run=Join-Path $root ('website-drill-'+$state.RunID)
        if([string]$state.RunFolder -cne $run -or -not (Test-Path -LiteralPath $run -PathType Container)){throw 'Recovery checkpoint folder differs.'}
        if(((Get-Item -LiteralPath $run).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'The checkpoint folder is a link; review required.'}
        if($state.LocalTOTPRestartRequested){
            if($state.ImportAttempted -or $state.ImportCommitted){throw 'An imported clone cannot resume a pre-import restart.'}
            $phase='Resuming interrupted local authenticator startup'
            $mutated=$true;$proxyTouched=$true;$resumedStartup=$true
            Invoke-DrillStackRestart $cli $work $run $package
        }
    }
    $phase='Checking existing recovery containers'
    $containers=@(Get-DrillContainers);$db=Get-DrillContainer 'supabase_db_StrokedRecoverySite'
    if($state.RunID){
        if(-not $resumedStartup -and $state.ContainerID -cne $db.Id){throw 'Recovery checkpoint does not match this local container.'}
        if($state.IsolationApplied){Assert-DrillIsolation}
        if(-not $db.State.Running){$null=Invoke-LocalDocker @('start','supabase_db_StrokedRecoverySite')}
    }
    Wait-DrillDatabaseReady
    $phase='Reading local database metadata';$local=Read-DrillMetadata
    if($resumedStartup){
        Confirm-DrillRestartMetadata $state $db $local
        Save-DrillCheckpoint
        $report.Checks.InterruptedLocalStartupRecovered=$true
    }
    if([string]$local.postgres -cnotmatch '^17\.'){throw 'PostgreSQL major17 is required for this backup.'}
    if([long]$local.outboundExtensions -ne 0){throw 'An outbound/scheduler extension is active in the local database; review needed.'}
    $marker=$null
    if($local.markerExists){
        $marker=ConvertFrom-Json -InputObject (Invoke-DrillSQL 'BEGIN READ ONLY; SELECT row_to_json(m)::text FROM stroked_recovery_drill.marker m; COMMIT;').Trim()
        if(-not $state.RunID -or $marker.run_id -cne $state.RunID -or $marker.source_commit -cne $state.SourceCommit){throw 'Existing restore marker does not match the checkpoint.'}
    }elseif([long]$local.authUsers -ne 0 -or [long]$local.appTables -ne 0){throw 'The local database contains unexpected data; it will not be overwritten.'}
    $phase='Finding the verified archive report'
    $previous=Get-ChildItem -LiteralPath $root -Filter 'recovery-check-report-*.json' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if(-not $previous){throw 'The previously verified archive report is missing.'}
    $old=Get-Content -LiteralPath $previous.FullName -Raw|ConvertFrom-Json
    if($old.downloadDecryptionContentCheckPassed -ne $true -or [string]$old.inputZipName -cnotmatch '^OneDrive_[0-9_\-]+\.zip$' -or [string]$old.sourceMainCommit -cnotmatch '^[a-f0-9]{40}$'){throw 'The verified downloaded set could not be identified.'}
    if($marker -and $state.SourceCommit -cne [string]$old.sourceMainCommit){throw 'Checkpoint source differs from the selected backup.'}
    $phase='Creating the private restore checkpoint'
    if(-not $state.RunID){
        $state=@{Project=$project;RunID=[Guid]::NewGuid().ToString('N');ContainerID=$db.Id;SourceCommit=[string]$old.sourceMainCommit;IsolationApplied=$false;ImportCommitted=$false}
        $run=Join-Path $root ('website-drill-'+$state.RunID);New-PrivateFolder $run;$state.RunFolder=$run;Save-DrillCheckpoint
    }
    $phase='Preparing isolated services and loopback proxy'
    $mutated=$true;$proxyTouched=$true
    $needsMigration=@($containers|Where-Object {@($_.NetworkSettings.Networks.PSObject.Properties.Name).Count -ne 1 -or $_.NetworkSettings.Networks.PSObject.Properties.Name -cne 'stroked-recovery-internal'}).Count -ne 0
    if($needsMigration){Stop-AllDrillContainers;$containers=@(Get-DrillContainers);Set-DrillIsolation $containers}else{Assert-DrillIsolation}
    $state.IsolationApplied=$true;Save-DrillCheckpoint
    Ensure-DrillProxy $run $package
    $db=Get-DrillContainer 'supabase_db_StrokedRecoverySite'
    if(-not $db.State.Running){$null=Invoke-LocalDocker @('start','supabase_db_StrokedRecoverySite')}
    Wait-DrillDatabaseReady
    $report.Checks.LoopbackProxyConfigured=$true
    $report.Checks.ApplicationContainersInternalOnly=$true
    $report.SourceCommit=$state.SourceCommit
    $report.Checks.Postgres=[string]$local.postgres
    $report.Checks.FirewallMatchesExpectedScope=$true
    $stage=Join-Path $run ('private-stage-'+[Guid]::NewGuid().ToString('N'));New-PrivateFolder $stage
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    Write-Host '2/7 Opening the verified database, image and source pair privately...'
    $phase='Archive pair and executable import plan'
    $outerPath=Join-Path (Join-Path $env:USERPROFILE 'Downloads') ([string]$old.inputZipName)
    $outer=[IO.Compression.ZipFile]::OpenRead($outerPath)
    try{
        $set=Get-StrokedCloudSetEntries $outer
        $inputs=@{}
        foreach($component in @('database','files')){
            $entry=$set[$component][0]
            $name=($entry.FullName.Replace('\','/') -split '/')[-1]
            if($name -cne [string]$old.($component+'Archive')){throw 'Downloaded archive name differs from the verified report.'}
            $target=Join-Path $stage ($component+'.zip.age');Copy-StrokedZipEntry $entry $target;$inputs[$component]=$target
        }
    }finally{$outer.Dispose()}
    $identity=Join-Path $root 'recovery-key.txt'
    if(-not (Test-Path -LiteralPath $identity -PathType Leaf)){throw 'Existing local recovery identity is missing.'}
    $recipient=(Invoke-QuietNative $keygen @('-y',$identity)).Trim()
    if($recipient -cnotmatch '^age1[0-9a-z]{20,100}$'){throw 'Unexpected recovery identity format.'}
    foreach($component in @('database','files')){$null=Invoke-QuietNative $age @('--decrypt','-i',$identity,'-o',(Join-Path $stage ($component+'.zip')),$inputs[$component]) 120}
    $dbChecked=Test-StrokedArchiveManifest (Join-Path $stage 'database.zip') 'database' $recipient
    $filesChecked=Test-StrokedArchiveManifest (Join-Path $stage 'files.zip') 'storage-source-supabase-reference' $recipient
    $pair=$filesChecked.Manifest.databaseArchive
    if($pair.name -cne [string]$old.databaseArchive -or [long]$pair.bytes -ne (Get-Item -LiteralPath $inputs.database).Length -or [string]$pair.sha256 -ine (Get-FileHash -LiteralPath $inputs.database).Hash -or $filesChecked.Manifest.sourceMainCommit -cne $state.SourceCommit){throw 'Database, image and source archives are not the verified pair.'}
    $payload=Join-Path $stage 'sql';$null=New-Item -ItemType Directory -Path $payload
    $databaseZip=[IO.Compression.ZipFile]::OpenRead((Join-Path $stage 'database.zip'))
    try{
        $entries=Get-StrokedZipFileEntries $databaseZip
        foreach($name in @('schema.sql','data.sql','managed-schema-reference.sql')){Copy-StrokedZipEntry $entries[$name] (Join-Path $payload $name)}
        $headers=@(Read-CopyHeaders $entries['data.sql'])
    }finally{$databaseZip.Dispose()}
    $comparison=Compare-ManagedCopyColumns $headers $local.columns
    if(-not $comparison.ColumnPresenceMatches){throw 'Managed-column compatibility requires review; no import performed.'}
    $report.Checks.ManagedColumnPresencePassed=$true
    $report.Checks.AutomaticManagedColumnsHandled=@($comparison.AutomaticLocalColumnsOmittedCorrectly)
    $plan=New-DrillImportPlan $payload $dbChecked.Manifest $state.RunID $state.SourceCommit $payload
    $report.Checks.TableCountsComparedDuringImport=$plan.TablesCompared
    $report.Checks.IntentionallyExcludedDataTables=$plan.Data.Skipped
    $report.Checks.RoleDumpReplayed=$false
    $report.Checks.ManagedDDLReplayed=$false
    $report.Checks.CompatibilityRoleReferences=$plan.CompatibilityRoleReferences
    $report.Checks.CompatibilityRoleRule='Only missing referenced cloud roles may be created NOLOGIN/NOINHERIT; existing roles, passwords and memberships are preserved.'
    $report.Checks.VaultProviderSecretsLoaded=$false
    $report.Checks.ProductionSessionsReplayed=$false
    $report.Checks.AuthImportScope='Users, identities, MFA factors and MFA recovery-code tables. Other Auth service/provider/session state stays local.'
    $report.Checks.LocalPendingAccountTokensCleared=$true
    $report.Checks.StorageImportScope='Bucket/object metadata and separately restored file bytes. Lifecycle/multipart operational state stays out of this test.'
    $bundle=Join-Path $stage 'source.bundle'
    $filesZip=[IO.Compression.ZipFile]::OpenRead((Join-Path $stage 'files.zip'))
    try{Copy-StrokedZipEntry ($filesZip.GetEntry('Stroked-source.bundle')) $bundle}finally{$filesZip.Dispose()}
    $bare=Join-Path $stage 'source.git'
    $null=Invoke-QuietNative $git @('-c','core.hooksPath=NUL','-c','credential.helper=','-c','credential.interactive=false','clone','--bare',$bundle,$bare) 60
    $commit=(Invoke-QuietNative $git @('-C',$bare,'rev-parse','refs/heads/main')).Trim()
    if($commit -cne $state.SourceCommit){throw 'Source bundle main commit differs.'}
    $sourceZip=Join-Path $stage 'website-source.zip'
    $null=Invoke-QuietNative $git @('-C',$bare,'archive','--format=zip',('--output='+$sourceZip),$commit) 60

    Write-Host '3/7 Isolating only the local recovery containers...'
    $phase='Local network isolation'
    $mutated=$true
    Set-DrillIsolation $containers
    $state.IsolationApplied=$true;Save-DrillCheckpoint
    $report.Checks.InternalRecoveryNetworkVerified=$true
    $authSettings=Get-ContainerValues (Get-DrillContainer 'supabase_auth_StrokedRecoverySite')
    if($authSettings['GOTRUE_MFA_TOTP_VERIFY_ENABLED'] -cne 'true'){
        $phase='Local authenticator verification configuration'
        if($marker -or $state.ImportAttempted){throw 'An imported clone requires a separate guarded MFA configuration review.'}
        $startHelp=Invoke-QuietNative $cli @('start','--help')
        $stopHelp=Invoke-QuietNative $cli @('stop','--help')
        if($startHelp -notmatch '--workdir' -or $startHelp -notmatch '--network-id' -or $stopHelp -notmatch '--workdir'){throw 'Existing local CLI restart flags differ.'}
        $config=Join-Path $work 'supabase\config.toml'
        $before=[IO.File]::ReadAllBytes($config)
        $text=[Text.Encoding]::UTF8.GetString($before).TrimStart([char]0xfeff)
        $updated=Enable-DrillTOTPConfig $text
        $backup=Join-Path $run ('local-config-before-mfa-'+[Guid]::NewGuid().ToString('N')+'.toml')
        [IO.File]::WriteAllBytes($backup,$before)
        if([Convert]::ToBase64String([IO.File]::ReadAllBytes($config)) -cne [Convert]::ToBase64String($before)){throw 'Local config changed concurrently.'}
        [IO.File]::WriteAllText($config,$updated,(New-Object Text.UTF8Encoding($false)))
        $state.LocalTOTPRestartRequested=$true;Save-DrillCheckpoint
        Write-Host 'Enabling authenticator verification in the still-empty local recovery copy...'
        $proxyTouched=$true
        Invoke-DrillStackRestart $cli $work $run $package
        $containers=@(Get-DrillContainers);$db=Get-DrillContainer 'supabase_db_StrokedRecoverySite' -RequireRunning
        Set-DrillIsolation $containers
        $after=Read-DrillMetadata
        Confirm-DrillRestartMetadata $state $db $after
        Save-DrillCheckpoint
        $report.Checks.LocalMFAConfigBackupSaved=$true
    }
    $authSettings=Get-ContainerValues (Get-DrillContainer 'supabase_auth_StrokedRecoverySite')
    if($authSettings['GOTRUE_MFA_TOTP_VERIFY_ENABLED'] -cne 'true'){throw 'Local authenticator verification did not become enabled.'}
    $report.Checks.LocalAuthenticatorVerificationEnabled=$true
    # Start only the needed local services, then verify mail routing before import.
    foreach($suffix in @('auth','rest','storage','inbucket','kong')){
        $name='supabase_'+$suffix+'_StrokedRecoverySite';$row=Get-DrillContainer $name
        if(-not $row.State.Running){$null=Invoke-LocalDocker @('start',$name)}
    }
    $keys=Get-DrillKeys $cli $work
    Wait-DrillAPI $keys
    Assert-DrillAuth
    $report.Checks.LocalMailAndConfirmationVerified=$true

    Write-Host '4/7 Restoring core website data in one guarded transaction...'
    $phase='Core managed-database import'
    if(-not $marker){
        $admin=(Invoke-DrillSQL 'BEGIN READ ONLY; SELECT rolsuper FROM pg_roles WHERE rolname=current_user; COMMIT;' 'supabase_admin').Trim()
        if($admin -cne 't'){throw 'Expected local restore administrator is unavailable.'}
        Stop-DrillApplicationServices
        Assert-DrillIsolation
        $state.ImportAttempted=$true;Save-DrillCheckpoint
        $null=Invoke-LocalDocker @('exec','--user','root','supabase_db_StrokedRecoverySite','rm','-rf','/tmp/stroked-drill-sql')
        $null=Invoke-LocalDocker @('exec','--user','root','supabase_db_StrokedRecoverySite','mkdir','-m','700','/tmp/stroked-drill-sql')
        foreach($name in @('import.sql','selected-data.sql')){$null=Invoke-LocalDocker @('cp',(Join-Path $payload $name),('supabase_db_StrokedRecoverySite:/tmp/stroked-drill-sql/'+$name))}
        $null=Invoke-LocalDocker @('exec','--user','root','supabase_db_StrokedRecoverySite','chown','-R','postgres:postgres','/tmp/stroked-drill-sql')
        $null=Invoke-LocalDocker @('exec','--user','root','supabase_db_StrokedRecoverySite','chmod','-R','go-rwx','/tmp/stroked-drill-sql')
        $null=Invoke-QuietNative $script:docker @('--host','npipe:////./pipe/docker_engine','exec','supabase_db_StrokedRecoverySite','psql','-U','supabase_admin','-d','postgres','-X','-q','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate','-f','/tmp/stroked-drill-sql/import.sql') 180
        $state.ImportCommitted=$true;$state.TableCountsCompared=$plan.TablesCompared;Save-DrillCheckpoint
    }else{$state.ImportCommitted=$true;Save-DrillCheckpoint;$report.Checks.ImportResumedFromCheckpoint=$true}
    $report.Checks.ImportCommitted=$true
    $phase='Restored table permissions'
    $report.Checks.ProtectedTableGrantsBefore=Read-DrillProtectedTableGrants
    $protectedACL=New-DrillProtectedTableACLPlan (Join-Path $payload 'schema.sql') $state.RunID $state.SourceCommit
    $null=Invoke-DrillSQL $protectedACL.SQL 'supabase_admin'
    $report.Checks.ProtectedTableACLReplayedFromVerifiedArchive=$true
    $report.Checks.ProtectedTableACLSourceStatementCount=$protectedACL.StatementCount
    $report.Checks.ProtectedTableGrantsAfter=Read-DrillProtectedTableGrants
    $phase='Restored database protections'
    $core=[IO.File]::ReadAllText((Join-Path $package 'verify-core.sql'))
    $null=Invoke-DrillSQL $core 'supabase_admin'
    $report.Checks.DatabaseProtectionChecksPassed=$true
    $encryptedMFA=(Invoke-DrillSQL "BEGIN READ ONLY; SELECT count(*) FROM auth.mfa_factors WHERE factor_type='totp' AND secret LIKE '{%'; COMMIT;").Trim()
    $report.Checks.RestoredMFAFactorsWithEncryptedEnvelope=[long]$encryptedMFA
    $report.Checks.RestoredMFACompatibilityNote='Factor rows are preserved. Actual Auth verification is required; encrypted factors can depend on the original Auth encryption configuration. No factors are reset or bypassed.'
    $people=ConvertFrom-Json -InputObject (Invoke-DrillSQL "BEGIN READ ONLY; SELECT json_build_object('users',(SELECT coalesce(json_agg(id::text),'[]'::json) FROM auth.users WHERE email NOT LIKE '%@recovery.invalid'),'admins',(SELECT coalesce(json_agg(user_id::text),'[]'::json) FROM stroked_live_v55.admin_security)); COMMIT;").Trim()
    $restoredIDs=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $adminIDs=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($id in @($people.users)){$null=$restoredIDs.Add([string]$id)}
    foreach($id in @($people.admins)){$null=$adminIDs.Add([string]$id)}
    if($adminIDs.Count -lt 1){throw 'Restored administrator MFA records are absent.'}
    $null=Invoke-LocalDocker @('exec','--user','root','supabase_db_StrokedRecoverySite','rm','-rf','/tmp/stroked-drill-sql')

    Write-Host '5/7 Starting the local APIs and restoring image files...'
    $phase='Local service restart and images'
    Start-DrillApplicationServices
    Wait-DrillAPI $keys
    Assert-ScopedFirewall;Assert-DrillIsolation;Assert-DrillAuth
    Wait-DrillStorage $keys
    $count=Restore-DrillObjects (Join-Path $stage 'files.zip') $filesChecked.Manifest $keys
    $report.Checks.ImagesRestoredAndHashChecked=$count
    $report.Checks.StorageMetadataNote='Objects were restored by their recorded bucket/key through the local Storage API. Byte hashes were verified; API version/timestamp metadata can change.'
    $public=Invoke-DrillHTTP 'http://127.0.0.1:54321/rest/v1/rpc/stroked_live_v55_public_events' 'POST' @{apikey=$keys.Anon;Authorization=('Bearer '+$keys.Anon)} ([Text.Encoding]::UTF8.GetBytes('{}'))
    $report.Checks.PublicListingsHTTPStatus=$public.Status
    if($public.Status -ne 200){throw 'Restored public event listing RPC did not succeed.'}
    $report.Checks.PublicListingsAPICheckPassed=$true
    $storagePaths=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($item in @($filesChecked.Manifest.storageObjects)){$null=$storagePaths.Add([string]$item.bucket+'/'+[string]$item.key)}

    Write-Host '6/7 Preparing the recovered website with loopback-only connections...'
    $phase='Recovered source website'
    $web=Join-Path $run 'web'
    Restore-DrillWebFiles $sourceZip $web $keys.Anon $package
    # The previous preparation already verified these templates/confirmation settings.
    $report.Checks.ArchivedSourceRestored=$true
    $report.Checks.ArchivedSourcePredatesLatestLiveFixes='Not compared to current production'
    if($state.SourceCommit -ceq '5557ed06e17d55286cf67397544051cb30e37f39'){$report.Checks.ArchivedSourcePredatesLatestLiveFixes=$true}
    $report.Checks.BrowserAPITarget='http://127.0.0.1:54321'
    $report.Checks.BrowserServerTarget='http://127.0.0.1:3000'
    $report.Checks.BrowserExternalConnectionsBlockedByCSP=$true
    $phase='Disposable local account checks'
    if($state.TestIDs){
        $stale=@{};foreach($p in $state.TestIDs.PSObject.Properties){$stale[$p.Name]=$p.Value}
        if($stale.ConfirmID -or $stale.ResetID){$stale.MessageIDs=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal);Remove-DrillTestUsers $stale $keys}
    }
    $test=New-DrillTestUsers $keys
    $state.TestIDs=@{ConfirmID=$test.ConfirmID;ConfirmEmail=$test.ConfirmEmail;ResetID=$test.ResetID;ResetEmail=$test.ResetEmail};Save-DrillCheckpoint
    Remove-Item -LiteralPath $stage -Recurse -Force;$stage=$null
    $report.Checks.DecryptedTemporaryFilesRemoved=$true
    $report.Result='Core data restored; browser checks pending'
    $null=Write-DrillSafeReport $report $reportPath
    $lock.Dispose();$lock=$null
    Write-Host '7/7 Opening the local browser checks. No more command pastes are needed.'
    $phase='Browser website/Auth tests'
    Start-DrillBrowserServer $web $package $report $reportPath $keys $test $restoredIDs $adminIDs $storagePaths
    $report.Result='Local drill ended; assess recorded checks'
} catch {
    if($script:LastNativeFailure){$report.PrimaryNativeFailure=$script:LastNativeFailure}
    $report.Result='Stopped; review required'
    $report.StoppedAt=$phase
    if($script:StartupPhase){$report.LocalStartupStep=$script:StartupPhase}
    $report.ErrorCode='LOCAL_WEBSITE_RECOVERY_DID_NOT_COMPLETE'
    $report.Failure=Get-DrillFailureSummary $_ $package
    if($phase -cin @('Restored table permissions','Restored database protections') -and $script:LastNativeFailure.SafeCheckID -cmatch '^DBP0[1-8]\b'){$report.Checks.DatabaseProtectionFailureCode=$script:LastNativeFailure.SafeCheckID}
    if($script:LastDataExportIssue){$report.DataExportParser=$script:LastDataExportIssue}
    if($script:LastSQLState -cmatch '^[0-9A-Z]{5}$'){$report.SQLState=$script:LastSQLState}
    Write-Host ('Stopped at: '+$phase+'. Attach the generated JSON report; no passwords or private logs are needed.') -ForegroundColor Yellow
    if($report.Failure.Detail){Write-Host $report.Failure.Detail -ForegroundColor Yellow}
} finally {
    if($script:ActiveTestState -and $keys -and -not $report.Checks.SyntheticAccountsRemoved){
        try{Remove-DrillTestUsers $script:ActiveTestState $keys;$report.Checks.SyntheticAccountsRemoved=$true}catch{$report.Checks.SyntheticAccountCleanupNeedsReview=$true}
    }
    if($mutated -and $state.ImportAttempted){
        try{$row=Get-DrillContainer 'supabase_db_StrokedRecoverySite';if($row.State.Running){$null=Invoke-LocalDocker @('exec','--user','root','supabase_db_StrokedRecoverySite','rm','-rf','/tmp/stroked-drill-sql')}}catch{$report.Checks.ContainerSQLCleanupNeedsReview=$true}
    }
    if($mutated -and -not $report.Checks.LocalServicesStopped){
        try{Stop-AllDrillContainers;$report.Checks.LocalServicesStopped=$true}catch{$report.Checks.LocalServicesStopped=$false;if($script:LastNativeFailure){$report.CleanupNativeFailure=$script:LastNativeFailure}}
    }
    if($proxyTouched){try{Stop-DrillProxy;$report.Checks.LoopbackProxyStopped=$true}catch{$report.Checks.LoopbackProxyStopped=$false}}
    if($stage -and (Test-Path -LiteralPath $stage)){
        try{Remove-Item -LiteralPath $stage -Recurse -Force;$report.Checks.DecryptedTemporaryFilesRemoved=$true}catch{$report.Checks.DecryptedTemporaryFilesRemoved=$false}
    }
    if($lock){$lock.Dispose()}
    if($drillLock){$drillLock.Dispose()}
    if($report.Checks.LocalCloneRemoved -and $state.RunID){
        $ownedRun=Join-Path $root ('website-drill-'+$state.RunID)
        try{
            if($state.RunFolder -cne $ownedRun -or ((Get-Item -LiteralPath $ownedRun).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Cleanup folder identity differs.'}
            Remove-Item -LiteralPath $ownedRun -Recurse -Force
            if(Test-Path -LiteralPath $statePath){$latest=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json;if($latest.RunID -ceq $state.RunID){Remove-Item -LiteralPath $statePath -Force}}
            $report.Checks.LocalTemporaryWebsiteFilesRemoved=$true
        }catch{$report.Checks.LocalTemporaryWebsiteFilesRemoved=$false}
    }
    $report.FinishedUTC=[DateTime]::UtcNow.ToString('o')
    $null=Write-DrillSafeReport $report $reportPath
    Write-Host ''
    Write-Host 'Safe recovery report:' -ForegroundColor Green
    Write-Host $reportPath
    try {
        Set-Clipboard -Value ([IO.File]::ReadAllText($reportPath)) -ErrorAction Stop
        Write-Host 'Return to our chat and press Ctrl+V to paste the safe report.' -ForegroundColor Green
    } catch {}
    Write-Host 'The live site and original encrypted archives were not changed.'
}

