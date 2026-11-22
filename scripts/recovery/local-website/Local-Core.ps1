function Invoke-QuietNative {
    param([string]$Program,[string[]]$Arguments,[int]$TimeoutSeconds=30,[string]$InputText=$null)
    # A typed string parameter coerces $null to ''. Only the bound-parameter
    # table distinguishes omitted stdin from an explicitly supplied empty input.
    $script:LastNativeFailure=$null
    $hasInput=$PSBoundParameters.ContainsKey('InputText')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Program
    $quoted=@(foreach($arg in $Arguments) {
        if ($arg.Contains('"') -or $arg.Contains("`n") -or $arg.Contains("`r")) { throw 'Unsupported native argument.' }
        '"'+([regex]::Replace($arg,'(\\+)$','$1$1'))+'"'
    })
    $info.Arguments=$quoted -join ' '
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    if($hasInput){$info.RedirectStandardInput=$true}
    $info.EnvironmentVariables['DOCKER_HOST']='npipe:////./pipe/docker_engine'
    foreach($key in @('DOCKER_CONTEXT','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH')) { $info.EnvironmentVariables.Remove($key) }
    $info.EnvironmentVariables['GIT_CONFIG_NOSYSTEM']='1'
    $info.EnvironmentVariables['GIT_CONFIG_GLOBAL']='NUL'
    $proc=New-Object Diagnostics.Process
    $proc.StartInfo=$info
    try {
        [void]$proc.Start()
        $outTask=$proc.StandardOutput.ReadToEndAsync()
        $errTask=$proc.StandardError.ReadToEndAsync()
        if($hasInput){
            # StandardInputEncoding is absent on Windows PowerShell 5.1's
            # .NET Framework. Write explicit UTF-8 bytes through supported APIs.
            $bytes=[Text.Encoding]::UTF8.GetBytes($InputText)
            $stream=$proc.StandardInput.BaseStream
            $stream.Write($bytes,0,$bytes.Length);$stream.Flush()
            $proc.StandardInput.Close()
        }
        if(-not $proc.WaitForExit($TimeoutSeconds*1000)) {
            try {$proc.Kill()} catch {}
            throw 'Local command timed out.'
        }
        $text=$outTask.GetAwaiter().GetResult()
        $errorText=$errTask.GetAwaiter().GetResult()
        if($script:NativePrivateLogPrefix){
            [IO.File]::WriteAllText($script:NativePrivateLogPrefix+'-stdout.txt',$text,(New-Object Text.UTF8Encoding($false)))
            [IO.File]::WriteAllText($script:NativePrivateLogPrefix+'-stderr.txt',$errorText,(New-Object Text.UTF8Encoding($false)))
        }
        if($proc.ExitCode -ne 0) {
            if($errorText -match 'ERROR:\s+([0-9A-Z]{5})\b'){$script:LastSQLState=$Matches[1]}
            # Report operation/exit and bounded daemon-only error text. Never
            # include inspect JSON, SQL/exec output, CLI logs or environments.
            $operation='Local command'
            if([IO.Path]::GetFileName($Program) -ieq 'docker.exe'){
                $index=0;if($Arguments.Count -ge 3 -and $Arguments[0] -ceq '--host'){$index=2}
                if($Arguments.Count -gt $index -and $Arguments[$index] -cmatch '^(?:ps|inspect|network|start|stop|exec|cp|rm|volume|create|pull)$'){
                    $operation='Docker '+$Arguments[$index]
                    if($Arguments[$index] -cin @('network','volume') -and $Arguments.Count -gt ($index+1) -and $Arguments[$index+1] -cmatch '^(?:ls|inspect|create|connect|disconnect|rm)$'){$operation+=' '+$Arguments[$index+1]}
                }
            }
            if([IO.Path]::GetFileName($Program) -ieq 'supabase.exe' -and $Arguments[0] -cin @('start','stop','status')){$operation='Supabase '+$Arguments[0]}
            $script:LastNativeFailure=[ordered]@{Operation=$operation;ExitCode=[int]$proc.ExitCode}
            if($operation -ceq 'Docker exec' -and $errorText -match '\\bSTROKED_DRILL_CHECK_(DBP[0-9]{2})\\b'){$script:LastNativeFailure.SafeCheckID=$Matches[1]}
            if($operation -cmatch '^Docker (?:ps|inspect|network|start|stop|create|pull|volume)(?: |$)'){
                $line=@($errorText -split '\r?\n'|Where-Object {$_.Trim()}|Select-Object -First 1) -join ''
                $line=[regex]::Replace($line,'(?i)(AGE-SECRET-KEY-[A-Z0-9]+|sb_secret_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)','[redacted]')
                $line=[regex]::Replace($line,'(?i)(password|token|secret|authorization|api[_-]?key)\s*[:=]\s*\S+','$1=[redacted]')
                $line=[regex]::Replace($line,'(?i)[0-9a-f]{32,64}','<id>')
                $line=[regex]::Replace($line,'(?i)[A-Z]:\\[^\s"\r\n]+','<local-path>')
                $line=[regex]::Replace($line,'(?i)https?://[^\s]+','<url>')
                $script:LastNativeFailure.DockerError=$line.Substring(0,[Math]::Min(600,$line.Length))
            }
            if($operation -clike 'Supabase *'){
                $signals=New-Object 'Collections.Generic.List[string]'
                foreach($pair in @(@('connection refused','ConnectionRefused'),@('timed out|timeout','Timeout'),@('no such host|name resolution','DNSFailure'),@('unhealthy|not ready|health check','ReadinessFailure'),@('address already in use|port is already allocated','PortConflict'),@('failed to parse config|invalid config','ConfigurationFailure'),@('pull access denied|failed to pull','ImagePullFailure'))){if($errorText -match $pair[0]){$signals.Add($pair[1])}}
                $script:LastNativeFailure.Signals=@($signals.ToArray())
                $script:LastNativeFailure.Services=@([regex]::Matches($errorText,'supabase_(db|auth|rest|kong|storage|studio|pg_meta|inbucket|realtime|vector|analytics|edge_runtime)_StrokedRecoverySite')|ForEach-Object {$_.Groups[1].Value}|Sort-Object -Unique)
            }
            throw 'Local command failed. Raw output withheld.'
        }
        return $text
    } finally { $proc.Dispose() }
}

function Invoke-LocalDocker([string[]]$Arguments,[int]$TimeoutSeconds=30) {
    return Invoke-QuietNative $script:docker (@('--host','npipe:////./pipe/docker_engine')+$Arguments) $TimeoutSeconds
}

function Resolve-DrillLocalTool([string]$Name) {
    if($Name -cnotin @('docker.exe','age.exe','age-keygen.exe','git.exe')){throw 'Unexpected executable lookup.'}
    $found=@(Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if($found.Count -eq 1 -and (Test-Path -LiteralPath $found[0].Source -PathType Leaf)){return [string]$found[0].Source}
    # Fresh elevated terminals can miss PATH entries added by an existing install.
    # Search registered PATH directories and fixed installation locations only.
    $folders=New-Object 'Collections.Generic.List[string]'
    foreach($target in @('Machine','User')){
        $path=[Environment]::GetEnvironmentVariable('Path',[EnvironmentVariableTarget]$target)
        foreach($part in @($path -split ';')){if($part){$folders.Add([Environment]::ExpandEnvironmentVariables($part.Trim('"')))}}
    }
    if($env:ProgramFiles){
        if($Name -ceq 'docker.exe'){$folders.Add((Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'))}
        if($Name -ceq 'git.exe'){$folders.Add((Join-Path $env:ProgramFiles 'Git\cmd'));$folders.Add((Join-Path $env:ProgramFiles 'Git\bin'))}
    }
    if($env:LOCALAPPDATA){
        $folders.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
        if($Name -ceq 'git.exe'){$folders.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd'))}
    }
    if($env:USERPROFILE){$folders.Add((Join-Path $env:USERPROFILE 'StrokedTools\age'))}
    foreach($folder in $folders){
        try{if(-not [IO.Path]::IsPathRooted($folder)){continue};$candidate=Join-Path $folder $Name;if(Test-Path -LiteralPath $candidate -PathType Leaf){return [string]$candidate}}catch{}
    }
    switch -CaseSensitive ($Name){
        'docker.exe' {throw 'The existing local Docker executable was not found.'}
        'age.exe' {throw 'The existing local age executable was not found.'}
        'age-keygen.exe' {throw 'The existing local age-keygen executable was not found.'}
        'git.exe' {throw 'The existing local Git executable was not found.'}
    }
}

function Assert-DrillAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run the extracted launcher using Run as administrator.'}
    }finally{$identity.Dispose()}
}

function Get-DrillFailureSummary($Record,[string]$PackageRoot) {
    $result=[ordered]@{Category=[string]$Record.CategoryInfo.Category}
    $exception=$Record.Exception
    if($exception){
        $base=$exception.GetBaseException()
        $type=$base.GetType().FullName
        if($type -cmatch '^System\.[A-Za-z0-9_.+]+$'){$result.ExceptionType=$type}
        $result.HResult=[int]$base.HResult
        if($base -is [Net.Sockets.SocketException]){$result.SocketError=[string]$base.SocketErrorCode}
    }
    $files=@('Restore-Local-Website.ps1','Local-Core.ps1','Schema-Parser.ps1','Archive-Reader.ps1','Import-Plan.ps1','Website-Tools.ps1','Browser-Controller.ps1','Proxy-Tools.ps1')
    $name=[IO.Path]::GetFileName([string]$Record.InvocationInfo.ScriptName)
    if($name -cin $files){$result.ScriptFile=$name;$result.ScriptLine=[int]$Record.InvocationInfo.ScriptLineNumber}
    # Only a complete literal throw string already shipped in this public package
    # may be copied into the report. Never include raw native/SQL/private errors.
    $safe=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($file in $files){
        try{
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PackageRoot $file),[ref]$tokens,[ref]$errors)
            foreach($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.ThrowStatementAst]},$true)){
                $elements=@($node.Pipeline.PipelineElements)
                if($elements.Count -ne 1){continue}
                $expression=$elements[0].Expression
                if($expression -is [Management.Automation.Language.StringConstantExpressionAst]){$null=$safe.Add([string]$expression.Value)}
            }
        }catch{}
    }
    if($exception -and $safe.Contains([string]$exception.Message)){$result.Detail=[string]$exception.Message}
    return $result
}

function Get-ContainerValues($Container) {
    $values=@{}
    foreach($entry in $Container.Config.Env) {
        $pair=$entry -split '=',2
        if($pair.Count -eq 2){$values[$pair[0]]=$pair[1]}
    }
    return $values
}

function Assert-ScopedFirewall {
    $profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore)
    if($profiles.Count -ne 3 -or @( $profiles | Where-Object { [int]$_.Enabled -ne 1 }).Count -ne 0) { throw 'Expected enabled firewall profiles not present.' }
    $rule=Get-NetFirewallRule -PolicyStore ActiveStore -Name 'StrokedRecoverySite-BlockRemote'
    if([string]$rule.Enabled -cne 'True' -or [string]$rule.Direction -cne 'Inbound' -or
       [string]$rule.Action -cne 'Block' -or [string]$rule.Profile -cne 'Any') { throw 'Expected firewall rule does not match.' }
    $filter=$rule | Get-NetFirewallPortFilter
    if([string]$filter.Protocol -notin @('TCP','6')) { throw 'Expected TCP filter missing.' }
    $ports=@('54321','54322','54323','54324','54327')
    if(@(Compare-Object ($ports | Sort-Object) (@($filter.LocalPort) | Sort-Object)).Count -ne 0) { throw 'Expected firewall ports differ.' }
    $expected=@('0.0.0.0-126.255.255.255','128.0.0.0-255.255.255.255','::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
    $actual=@(($rule | Get-NetFirewallAddressFilter).RemoteAddress)
    if(@(Compare-Object ($expected | Sort-Object) ($actual | Sort-Object)).Count -ne 0) { throw 'Expected firewall address scope differs.' }
}

function New-PrivateFolder([string]$Path) {
    $null=New-Item -ItemType Directory -Path $Path
    $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $system=New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetOwner($owner); $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @($owner,$system)) {
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $null=$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Enable-DrillTOTPConfig([string]$Text) {
    $sections=[regex]::Matches($Text,'(?ms)^\[auth\.mfa\.totp\][ \t]*(?:#[^\r\n]*)?\r?\n(?<body>.*?)(?=^\[|\z)')
    if($sections.Count -gt 1){throw 'Duplicate local TOTP configuration sections.'}
    $newline="`n";if($Text.Contains("`r`n")){$newline="`r`n"}
    if($sections.Count -eq 0){
        if($Text -match '(?m)^\s*\[\s*auth\.mfa\.totp\s*\]'){throw 'Unsupported local TOTP section format.'}
        return $Text+$newline+'[auth.mfa.totp]'+$newline+'verify_enabled = true'+$newline
    }
    $section=$sections[0];$body=$section.Groups['body'].Value
    $keys=[regex]::Matches($body,'(?m)^(?<lead>[ \t]*verify_enabled[ \t]*=[ \t]*)(?<value>true|false)(?<tail>[ \t]*(?:#[^\r\n]*)?)\r?$')
    if($keys.Count -gt 1 -or ($keys.Count -eq 0 -and $body -match '(?m)^\s*verify_enabled\s*=')){throw 'Unsupported local TOTP verification setting.'}
    if($keys.Count -eq 1){
        $value=$keys[0].Groups['value'];$start=$section.Groups['body'].Index+$value.Index
        return $Text.Substring(0,$start)+'true'+$Text.Substring($start+$value.Length)
    }
    return $Text.Insert($section.Groups['body'].Index,'verify_enabled = true'+$newline)
}

function Read-CopyHeaders($Entry) {
    $reader=New-Object IO.StreamReader($Entry.Open(),[Text.Encoding]::UTF8)
    $tables=New-Object 'Collections.Generic.List[object]'
    $inCopy=$false
    try {
        while($null -ne ($line=$reader.ReadLine())) {
            if($inCopy) { if($line -ceq '\.'){$inCopy=$false}; continue }
            if($line -cmatch '^COPY (?<s>"?[a-z_][a-z0-9_]*"?)\.(?<t>"?[a-z_][a-z0-9_]*"?) \((?<cols>[^\r\n]+)\) FROM stdin;\s*$') {
                $schema=$Matches.s.Trim('"'); $table=$Matches.t.Trim('"'); $columnText=$Matches.cols
                $inCopy=$true
                if($schema -notin @('auth','storage','supabase_migrations')) { continue }
                $columns=@(foreach($c in ($columnText -split ',')) {
                    $id=$c.Trim().Trim('"')
                    if($id -cnotmatch '^[a-z_][a-z0-9_]*$'){throw 'Unsupported managed column identifier.'}
                    $id
                })
                $tables.Add([pscustomobject]@{Schema=$schema;Table=$table;Columns=$columns})
            } elseif($line -cmatch '^COPY\s') { throw 'Unsupported COPY header format.' }
        }
        if($inCopy){throw 'Incomplete COPY block.'}
    } finally {$reader.Dispose()}
    if(@($tables | Where-Object {$_.Schema -ceq 'auth' -and $_.Table -ceq 'users'}).Count -ne 1) { throw 'Auth users COPY header missing or duplicated.' }
    return $tables.ToArray()
}

function Compare-ManagedCopyColumns($Tables,$LocalColumns) {
    $missing=New-Object 'Collections.Generic.List[string]'
    $extraRequired=New-Object 'Collections.Generic.List[string]'
    $generatedInputs=New-Object 'Collections.Generic.List[string]'
    $automatic=New-Object 'Collections.Generic.List[string]'
    $localMap=@{}
    foreach($col in $LocalColumns) {$localMap[([string]$col.schema+'.'+[string]$col.table+'.'+[string]$col.column)]=$col}
    foreach($table in $Tables) {
        foreach($column in $table.Columns) {
            $key=$table.Schema+'.'+$table.Table+'.'+$column
            if(-not $localMap.ContainsKey($key)){$missing.Add($key)}
            elseif($localMap[$key].generated -ceq 'ALWAYS'){$generatedInputs.Add($key)}
        }
        foreach($col in @($LocalColumns | Where-Object {$_.schema -ceq $table.Schema -and $_.table -ceq $table.Table})) {
            if($col.column -cnotin $table.Columns) {
                $key=[string]$col.schema+'.'+[string]$col.table+'.'+[string]$col.column
                if($col.generated -ceq 'ALWAYS' -or $col.identity -ceq 'YES'){$automatic.Add($key)}
                elseif($col.nullable -ceq 'NO' -and -not $col.hasDefault){$extraRequired.Add($key)}
            }
        }
    }
    return [pscustomobject]@{
        Tables=@($Tables); MissingLocalColumns=@($missing.ToArray()); ExtraRequiredLocalColumns=@($extraRequired.ToArray())
        BackupAttemptsGeneratedInput=@($generatedInputs.ToArray()); AutomaticLocalColumnsOmittedCorrectly=@($automatic.ToArray())
        ColumnPresenceMatches=($missing.Count -eq 0 -and $extraRequired.Count -eq 0 -and $generatedInputs.Count -eq 0)
        Limit='Column-name and automatic-column handling only. Not a full type, constraint, role, Vault, scheduler or outbound isolation proof.'
    }
}
function ConvertFrom-DrillDockerArray([string]$Text) {
    if(-not $Text.TrimStart().StartsWith('[')){throw 'Docker inspection did not return a JSON array.'}
    # Decode inside an object: its array property is preserved identically on
    # Windows PowerShell 5.1 and newer PowerShell, including zero/one/many items.
    # Explicit enumeration prevents an extra outer array of all containers.
    $document=Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject ('{"Inspection":'+$Text+'}') -ErrorAction Stop
    foreach($item in $document.Inspection){
        if($null -eq $item -or $item -is [Array] -or $item -isnot [pscustomobject]){throw 'Docker inspection contained a non-object or nested array.'}
        Write-Output -NoEnumerate $item
    }
}
function Get-DrillContainer([string]$Name,[switch]$RequireRunning) {
    if($Name -cnotmatch '^supabase_[a-z0-9_]+_StrokedRecoverySite$'){throw 'Unexpected recovery container name.'}
    $items=@(ConvertFrom-DrillDockerArray -Text (Invoke-LocalDocker @('inspect',$Name)))
    if($items.Count -ne 1 -or $items[0].Name -cne ('/'+$Name) -or $items[0].Config.Labels.'com.supabase.cli.project' -cne 'StrokedRecoverySite'){throw 'Container identity did not match the recovery project.'}
    if($RequireRunning -and -not $items[0].State.Running){throw 'Required recovery container is not running.'}
    return $items[0]
}
function Get-DrillContainers {
    param([switch]$AllowIncomplete)
    $ids=(Invoke-LocalDocker @('ps','-aq','--filter','label=com.supabase.cli.project=StrokedRecoverySite')).Trim()
    if(-not $ids){if($AllowIncomplete){return};throw 'Local recovery containers are absent.'}
    $selectedIDs=@($ids -split '\s+')
    $rows=@(ConvertFrom-DrillDockerArray -Text (Invoke-LocalDocker (@('inspect')+$selectedIDs)))
    if($rows.Count -ne $selectedIDs.Count){throw 'Docker container count differs from the scoped selection.'}
    foreach($row in $rows){
        $name=$row.Name.TrimStart('/')
        if($name -cnotmatch '^supabase_[a-z0-9_]+_StrokedRecoverySite$' -or $row.Config.Labels.'com.supabase.cli.project' -cne 'StrokedRecoverySite'){throw 'Unexpected container in the recovery project selection.'}
    }
    if(-not $AllowIncomplete){foreach($suffix in @('db','auth','rest','storage','kong','inbucket')){if(@($rows | Where-Object {$_.Name -ceq ('/supabase_'+$suffix+'_StrokedRecoverySite')}).Count -ne 1){throw 'A required recovery service is missing.'}}}
    return $rows
}
function Assert-DrillAuth {
    $auth=Get-ContainerValues (Get-DrillContainer 'supabase_auth_StrokedRecoverySite' -RequireRunning)
    $mail=Get-ContainerValues (Get-DrillContainer 'supabase_inbucket_StrokedRecoverySite' -RequireRunning)
    if($auth['GOTRUE_SMTP_HOST'] -cne 'supabase_inbucket_StrokedRecoverySite' -or $auth['GOTRUE_SMTP_PORT'] -cne '1025' -or $auth['GOTRUE_MAILER_AUTOCONFIRM'] -cne 'false'){throw 'Expected local mail and confirmation settings differ.'}
    if($auth['GOTRUE_SECURITY_CAPTCHA_ENABLED'] -and $auth['GOTRUE_SECURITY_CAPTCHA_ENABLED'] -cne 'false'){throw 'The local recovery Auth service unexpectedly requires an external CAPTCHA.'}
    foreach($key in $auth.Keys){if($key -cmatch '^GOTRUE_HOOK_[A-Z0-9_]+_ENABLED$' -and $auth[$key] -cne 'false'){throw 'Enabled Auth hook requires review.'}}
    foreach($key in $mail.Keys){if($key -cmatch '^MP_SMTP_(?:RELAY|FORWARD)' -and $mail[$key] -and $mail[$key] -cne 'false'){throw 'Mail forwarding configuration requires review.'}}
    foreach($key in @('GOTRUE_SITE_URL','API_EXTERNAL_URL')){
        $u=[Uri]([string]$auth[$key]); if($u.Scheme -cne 'http' -or $u.Host -cne '127.0.0.1' -or $u.UserInfo){throw 'Auth URLs must stay on the expected loopback address.'}
        $expectedPort=3000;if($key -ceq 'API_EXTERNAL_URL'){$expectedPort=54321}
        if($u.Port -ne $expectedPort){throw 'Auth URL port differs from the recovery website/API.'}
    }
}
function Invoke-DrillSQL([string]$SQL,[string]$Role='postgres') {
    if($Role -cnotin @('postgres','supabase_admin')){throw 'Unexpected local database role.'}
    return Invoke-QuietNative $script:docker @('--host','npipe:////./pipe/docker_engine','exec','-i','supabase_db_StrokedRecoverySite','psql','-U',$Role,'-d','postgres','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate') 60 ($SQL+"`n")
}
function Read-DrillMetadata {
    $sql=@'
BEGIN READ ONLY;
SELECT json_build_object(
 'postgres',current_setting('server_version'),
 'authUsers',(SELECT count(*) FROM auth.users),
 'appTables',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p') AND (n.nspname='public' OR n.nspname LIKE 'stroked%') AND n.nspname<>'stroked_recovery_drill'),
 'columns',(SELECT coalesce(json_agg(json_build_object('schema',table_schema,'table',table_name,'column',column_name,'type',udt_name,'nullable',is_nullable,'hasDefault',column_default IS NOT NULL,'generated',is_generated,'identity',is_identity) ORDER BY table_schema,table_name,ordinal_position),'[]'::json) FROM information_schema.columns WHERE table_schema IN ('auth','storage')),
 'roles',(SELECT json_agg(rolname) FROM pg_roles),
 'outboundExtensions',(SELECT count(*) FROM pg_extension WHERE extname IN ('pg_cron','pg_net')),
 'markerExists',to_regclass('stroked_recovery_drill.marker') IS NOT NULL
)::text;
COMMIT;
'@
    return ConvertFrom-Json -InputObject (Invoke-DrillSQL $sql).Trim()
}
function Set-DrillIsolation($Containers) {
    $netName='stroked-recovery-internal'
    $existing=(Invoke-LocalDocker @('network','ls','-q','--filter',('name=^'+$netName+'$'))).Trim()
    if(-not $existing){$null=Invoke-LocalDocker @('network','create','--driver','bridge','--internal','--label','stroked.recovery=StrokedRecoverySite',$netName)}
    $net=@(ConvertFrom-DrillDockerArray -Text (Invoke-LocalDocker @('network','inspect',$netName)))
    if($net.Count -ne 1 -or -not $net[0].Internal -or $net[0].Driver -cne 'bridge' -or $net[0].Labels.'stroked.recovery' -cne 'StrokedRecoverySite'){throw 'Recovery internal network identity differs.'}
    $expected=@($Containers | ForEach-Object {$_.Id})
    foreach($attached in $net[0].Containers.PSObject.Properties){if($attached.Name -cnotin $expected){
        if($attached.Value.Name -ceq 'stroked_recovery_loopback_StrokedRecoverySite' -and (Get-DrillProxy).Id -ceq $attached.Name){continue}
        throw 'An unrelated container is on the recovery network.'
    }}
    foreach($row in $Containers){
        $name=$row.Name.TrimStart('/')
        $aliases=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $null=$aliases.Add($name)
        foreach($endpoint in $row.NetworkSettings.Networks.PSObject.Properties){foreach($alias in @($endpoint.Value.Aliases)){if($alias -cmatch '^[a-zA-Z0-9_.-]{1,128}$'){$null=$aliases.Add($alias)}}}
        if(-not $row.NetworkSettings.Networks.PSObject.Properties[$netName]){
            $connectArguments=@('network','connect')
            foreach($alias in $aliases){$connectArguments+=@('--alias',$alias)}
            $null=Invoke-LocalDocker ($connectArguments+@($netName,$name))
        }
        foreach($endpoint in @($row.NetworkSettings.Networks.PSObject.Properties)){
            if($endpoint.Name -cne $netName){$null=Invoke-LocalDocker @('network','disconnect',$endpoint.Name,$name)}
        }
    }
    Assert-DrillIsolation
}
function Assert-DrillIsolation {
    $net=@(ConvertFrom-DrillDockerArray -Text (Invoke-LocalDocker @('network','inspect','stroked-recovery-internal')))
    if($net.Count -ne 1 -or -not $net[0].Internal -or $net[0].Labels.'stroked.recovery' -cne 'StrokedRecoverySite'){throw 'Internal network verification failed.'}
    foreach($row in @(Get-DrillContainers)){
        $names=@($row.NetworkSettings.Networks.PSObject.Properties.Name)
        if($names.Count -ne 1 -or $names[0] -cne 'stroked-recovery-internal'){throw 'A recovery container still has another network connection.'}
    }
}
function Stop-DrillApplicationServices {
    foreach($row in @(Get-DrillContainers)){
        if($row.Name -cne '/supabase_db_StrokedRecoverySite' -and $row.State.Running){$null=Invoke-LocalDocker @('stop','--time','15',$row.Name.TrimStart('/'))}
    }
}
function Start-DrillApplicationServices {
    foreach($suffix in @('inbucket','auth','rest','storage','realtime','pg_meta','studio','kong')){
        $name='supabase_'+$suffix+'_StrokedRecoverySite'
        $row=@(Get-DrillContainers | Where-Object {$_.Name -ceq ('/'+$name)})
        if($row.Count -eq 1 -and -not $row[0].State.Running){$null=Invoke-LocalDocker @('start',$name)}
    }
    # Edge Functions, analytics and vector stay stopped during the drill.
}
function Invoke-DrillHTTP {
    param([string]$URI,[string]$Method='GET',[hashtable]$Headers=@{},[byte[]]$Body=$null,[string]$ContentType='application/json')
    $u=[Uri]$URI
    if($u.Scheme -cne 'http' -or $u.Host -cne '127.0.0.1' -or $u.Port -notin @(54321,54324,3000) -or $u.UserInfo){throw 'HTTP request outside the local drill was refused.'}
    $request=[Net.HttpWebRequest]::Create($u)
    $request.Method=$Method;$request.Proxy=$null;$request.AllowAutoRedirect=$false;$request.Timeout=20000;$request.ReadWriteTimeout=20000
    foreach($key in $Headers.Keys){$request.Headers[$key]=[string]$Headers[$key]}
    if($null -ne $Body){$request.ContentType=$ContentType;$request.ContentLength=$Body.Length;$writer=$request.GetRequestStream();try{$writer.Write($Body,0,$Body.Length)}finally{$writer.Dispose()}}
    $response=$null
    try {
        try{$response=$request.GetResponse()}catch [Net.WebException]{$response=$_.Exception.Response;if($null -eq $response){throw 'Local HTTP connection failed.'}}
        $memory=New-Object IO.MemoryStream
        try{$stream=$response.GetResponseStream();try{$stream.CopyTo($memory)}finally{$stream.Dispose()};$bytes=$memory.ToArray()}finally{$memory.Dispose()}
        return [pscustomobject]@{Status=[int]$response.StatusCode;Bytes=$bytes;Text=[Text.Encoding]::UTF8.GetString($bytes);Location=[string]$response.Headers['Location']}
    } finally{if($response){$response.Dispose()}}
}
function ConvertTo-DrillJSONBytes($Value){return [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 15 -Compress))}
