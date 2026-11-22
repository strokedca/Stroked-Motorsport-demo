#Requires -Version 5.1
[CmdletBinding()]
param([switch]$RequireWindows51,[string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
if($RequireWindows51 -and ($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1)){throw 'Actual Windows PowerShell 5.1 is required.'}
foreach($file in @(Get-ChildItem -LiteralPath $Package -Filter '*.ps1')){
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('Parse failed: '+$file.Name)}
}
. (Join-Path $Package 'Local-Core.ps1')
. (Join-Path $Package 'Browser-Controller.ps1')
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Throws([scriptblock]$Action,[string]$Message){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert-True $failed $Message}
function To-ArrayJSON([object[]]$Items){ConvertTo-Json -InputObject $Items -Depth 15 -Compress}
$script:Suffixes=@('studio','pg_meta','edge_runtime','storage','rest','realtime','inbucket','auth','kong','vector','analytics','db')
function Reset-Fixture {
    $script:Rows=@(for($i=0;$i -lt $script:Suffixes.Count;$i++){
        $name='supabase_'+$script:Suffixes[$i]+'_StrokedRecoverySite'
        [pscustomobject]@{Id=('{0:x64}' -f ($i+1));Name='/'+$name;State=[pscustomobject]@{Running=$true};Config=[pscustomobject]@{Labels=[pscustomobject]@{'com.supabase.cli.project'='StrokedRecoverySite'};Env=@('TOKEN=PRIVATE_INSPECT_SENTINEL')};NetworkSettings=[pscustomobject]@{Networks=[pscustomobject]@{'stroked-recovery-local'=[pscustomobject]@{Aliases=@($name,('alias-'+$i))}}}}
    })
    $script:Calls=New-Object 'Collections.Generic.List[object]'
    $script:NetExists=$false
    $script:NetForeign=$false
    $script:CountMismatch=$false
}
function Invoke-LocalDocker([string[]]$Arguments){
    $script:Calls.Add([pscustomobject]@{Arguments=[string[]]$Arguments})
    switch -CaseSensitive ($Arguments[0]){
        'ps' {return (($script:Rows|ForEach-Object {$_.Id}) -join "`n")}
        'inspect' {
            $selected=@(foreach($row in $script:Rows){if($row.Id -cin $Arguments -or $row.Name.TrimStart('/') -cin $Arguments){$row}})
            if($script:CountMismatch){return To-ArrayJSON @($selected[0])}
            return To-ArrayJSON $selected
        }
        'stop' {
            $selected=@($script:Rows|Where-Object {$_.Name -ceq ('/'+$Arguments[-1])})
            Assert-True ($selected.Count -eq 1 -and $Arguments.Count -eq 4) 'Stop must target one scalar scoped container.'
            $selected[0].State.Running=$false
            return $Arguments[-1]
        }
        'network' {
            switch -CaseSensitive ($Arguments[1]){
                'ls' {if($script:NetExists){return 'fixture-internal-id'};return ''}
                'create' {$script:NetExists=$true;return 'fixture-internal-id'}
                'inspect' {
                    $attached=[ordered]@{}
                    foreach($row in $script:Rows){if($row.NetworkSettings.Networks.PSObject.Properties['stroked-recovery-internal']){$attached[$row.Id]=[pscustomobject]@{Name=$row.Name.TrimStart('/')}}}
                    if($script:NetForeign){$attached['foreign-container']=[pscustomobject]@{Name='unrelated'}}
                    return To-ArrayJSON @([pscustomobject]@{Internal=$true;Driver='bridge';Labels=[pscustomobject]@{'stroked.recovery'='StrokedRecoverySite'};Containers=[pscustomobject]$attached})
                }
                'connect' {
                    $selected=@($script:Rows|Where-Object {$_.Name -ceq ('/'+$Arguments[-1])})
                    Assert-True ($selected.Count -eq 1 -and $Arguments[-2] -ceq 'stroked-recovery-internal') 'Connect must target one scalar scoped container.'
                    $aliases=@(for($i=2;$i -lt ($Arguments.Count-2);$i+=2){Assert-True ($Arguments[$i] -ceq '--alias') 'Unexpected connect option.';$Arguments[$i+1]})
                    $selected[0].NetworkSettings.Networks|Add-Member -NotePropertyName 'stroked-recovery-internal' -NotePropertyValue ([pscustomobject]@{Aliases=$aliases})
                    return ''
                }
                'disconnect' {
                    $selected=@($script:Rows|Where-Object {$_.Name -ceq ('/'+$Arguments[-1])})
                    Assert-True ($selected.Count -eq 1 -and $Arguments.Count -eq 4) 'Disconnect must target one scalar scoped container.'
                    $selected[0].NetworkSettings.Networks.PSObject.Properties.Remove($Arguments[2]);return ''
                }
                default {throw 'Unexpected network operation in fixture.'}
            }
        }
        default {throw 'Unexpected Docker operation in fixture.'}
    }
}
Reset-Fixture
$json=To-ArrayJSON $script:Rows
$old=@(Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $json)
if($RequireWindows51){
    Assert-True ($old.Count -eq 1 -and $old[0] -is [Array]) 'Original Windows 5.1 extra-array failure did not reproduce.'
    $brokenNetworks=@($old[0].NetworkSettings.Networks.PSObject.Properties.Name)
    Assert-True ('Count' -cin $brokenNetworks -and 'Length' -cin $brokenNetworks) 'Original wrong network-property names did not reproduce.'
    Assert-True (([string]$old[0].Name) -like '*supabase_studio*supabase_db*') 'Original joined container names did not reproduce.'
    Write-Host 'Reproduced owner failure: nested array, joined names, Count/Length network properties.'
}
Assert-True (@(ConvertFrom-DrillDockerArray '[]').Count -eq 0) 'Empty inspection failed.'
Assert-True (@(ConvertFrom-DrillDockerArray '[{"Name":"one"}]').Count -eq 1) 'Singleton inspection failed.'
Assert-True (@(ConvertFrom-DrillDockerArray $json).Count -eq 12) 'Twelve-object inspection failed.'
foreach($bad in @('{}','[[]]','[[{"Name":"nested"}]]','[1]','[null]','["text"]','[{}')){Assert-Throws {ConvertFrom-DrillDockerArray $bad} 'Malformed or nested inspection accepted.'}
$rows=@(Get-DrillContainers)
Assert-True ($rows.Count -eq 12) 'Scoped containers were not flattened.'
Assert-True (@($rows|Where-Object {$_ -is [Array]}).Count -eq 0) 'A nested array escaped decoding.'
$db=Get-DrillContainer 'supabase_db_StrokedRecoverySite' -RequireRunning
Assert-True ($db.Id -ceq ('{0:x64}' -f 12)) 'Scalar database ID/checkpoint comparison failed.'
Set-DrillIsolation $rows
foreach($row in @(Get-DrillContainers)){
    Assert-True (@($row.NetworkSettings.Networks.PSObject.Properties).Count -eq 1) 'External network was retained.'
    Assert-True ($row.NetworkSettings.Networks.'stroked-recovery-internal'.Aliases.Count -eq 2) 'Aliases were not preserved.'
}
$connects=@($script:Calls|Where-Object {$_.Arguments[0] -ceq 'network' -and $_.Arguments[1] -ceq 'connect'})
Assert-True ($connects.Count -eq 12) 'Expected twelve individually scoped connects.'
$before=$script:Calls.Count
Set-DrillIsolation @(Get-DrillContainers)
Assert-True (@($script:Calls|Select-Object -Skip $before|Where-Object {$_.Arguments[0] -ceq 'network' -and $_.Arguments[1] -cin @('connect','disconnect','create')}).Count -eq 0) 'Already-isolated resume changed networks.'
Stop-AllDrillContainers
Assert-True (@($script:Rows|Where-Object {$_.State.Running}).Count -eq 0) 'Cleanup left a running test container.'
Assert-True (@($script:Calls|Where-Object {$_.Arguments[0] -ceq 'stop'}).Count -eq 12) 'Expected twelve individually scoped stops.'
Reset-Fixture;$script:Rows[0].Config.Labels.'com.supabase.cli.project'='foreign'
Assert-Throws {Get-DrillContainers} 'Foreign project label accepted.'
Reset-Fixture;$script:Rows=@($script:Rows|Where-Object {$_.Name -cne '/supabase_auth_StrokedRecoverySite'})
Assert-Throws {Get-DrillContainers} 'Missing required service accepted.'
Reset-Fixture;$script:CountMismatch=$true
Assert-Throws {Get-DrillContainers} 'Mismatched inspection count accepted.'
Reset-Fixture;$script:NetExists=$true;$script:NetForeign=$true
Assert-Throws {Set-DrillIsolation @(Get-DrillContainers)} 'Foreign attached container accepted.'
Assert-True (@($script:Calls|Where-Object {$_.Arguments[0] -ceq 'network' -and $_.Arguments[1] -cin @('connect','disconnect')}).Count -eq 0) 'Foreign network guard ran too late.'
if($RequireWindows51){
    # Exercise the shipped ProcessStartInfo runner on actual .NET Framework.
    $child=Join-Path $PSHOME 'powershell.exe'
    $command="[Console]::InputEncoding=[Text.Encoding]::UTF8;([Console]::In.ReadToEnd()).Length"
    $unicode=[string][char]0x00e9+[string][char]0x6f22
    Assert-True ((Invoke-QuietNative $child @('-NoLogo','-NoProfile','-NonInteractive','-Command',$command) 20 $unicode).Trim() -ceq '2') 'Real Windows 5.1 UTF-8 stdin failed.'
    Assert-True ((Invoke-QuietNative $child @('-NoLogo','-NoProfile','-NonInteractive','-Command',"'omitted-input-ok'")).Trim() -ceq 'omitted-input-ok') 'Real Windows 5.1 omitted stdin failed.'
    Assert-Throws {Invoke-QuietNative $child @('-NoLogo','-NoProfile','-NonInteractive','-Command',"[Console]::Error.WriteLine('PRIVATE_NATIVE_SENTINEL');exit 17")} 'Nonzero native exit accepted.'
    Assert-True ($script:LastNativeFailure.ExitCode -eq 17) 'Safe numeric native exit was lost.'
    Assert-True (($script:LastNativeFailure|ConvertTo-Json) -notmatch 'PRIVATE_NATIVE_SENTINEL') 'Native stderr entered report metadata.'
    $assertionCommand="[Console]::Error.WriteLine('ERROR: P0001: STROKED_DRILL_CHECK_DBP03 PRIVATE_OUTPUT_SENTINEL');exit 3"
    Assert-Throws {Invoke-QuietNative $child @('-NoLogo','-NoProfile','-NonInteractive','-Command',$assertionCommand)} 'Database assertion failure was accepted.'
    Assert-True ($script:LastNativeFailure.SafeCheckID -ceq 'DBP03') 'Safe database protection identifier was not captured.'
    Assert-True (($script:LastNativeFailure|ConvertTo-Json) -notmatch 'PRIVATE_OUTPUT_SENTINEL') 'Private SQL output entered report metadata.'
}
Write-Host ('PASS: PowerShell '+$PSVersionTable.PSVersion+'; flat zero/one/twelve objects, scalar checkpoint ID, individual network/cleanup targets, resume, scope guards and safe failures.')
