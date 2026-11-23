#Requires -Version 5.1
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Schema-Parser.ps1')
. (Join-Path $Package 'Import-Plan.ps1')
. (Join-Path $Package 'Routine-ACL.ps1')
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Throws([scriptblock]$Action,[string]$Message){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert-True $failed $Message}
$root=Join-Path ([IO.Path]::GetTempPath()) ('stroked-rpc-plan-'+[guid]::NewGuid().ToString('N'))
try{
    $null=New-Item -ItemType Directory -Path $root
    $path=Join-Path $root 'schema.sql'
    $schema=@'
CREATE FUNCTION public.admin_pending_events() RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION public.get_pending_events() RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION public.is_event_admin() RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION public.stroked_live_v55_admin_events() RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION "stroked_live_v55"."test_args"(p_id uuid,p_amount numeric) RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION auth.managed_test() RETURNS boolean LANGUAGE sql AS 'SELECT false';
REVOKE ALL ON FUNCTION "public"."admin_pending_events"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_pending_events"() TO service_role;
GRANT EXECUTE ON FUNCTION "stroked_live_v55"."test_args"(p_id uuid,p_amount numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION auth.managed_test() TO anon;
GRANT EXECUTE ON FUNCTION public.unknown_function() TO anon;
GRANT SELECT ON TABLE public.unrelated TO anon;
CREATE FUNCTION public.literal_only() RETURNS text LANGUAGE sql AS $$SELECT 'GRANT EXECUTE ON FUNCTION public.fake() TO anon;'$$;
'@
    [IO.File]::WriteAllText($path,$schema,(New-Object Text.UTF8Encoding($false)))
    $plan=New-DrillRoutineACLPlan $path ('a'*32) ('b'*40)
    Assert-True ($plan.StatementCount -eq 3) 'Routine plan did not select exactly the three source-owned ACL statements.'
    Assert-True ($plan.SQL -notmatch 'managed_test|unknown_function|public.unrelated|public.fake') 'An unmanaged identity or routine literal entered the routine ACL plan.'
    Assert-True ($plan.SQL -match 'stroked_recovery_drill.marker' -and $plan.SQL -match 'PDB05' -and $plan.SQL -match 'PDB06') 'Routine checkpoint or both post-replay gates are missing.'
    Assert-DrillSingleRoutineIdentity 'public.test_args("odd(type)" uuid,n numeric(10,2))'
    function Invoke-DrillSQL([string]$SQL,[string]$Role){return '[{"Signature":"one","AnonExecute":false},{"Signature":"two","AnonExecute":false},{"Signature":"three","AnonExecute":false},{"Signature":"four","AnonExecute":true}]'}
    $rows=@(Read-DrillCoreRoutineGrants)
    Assert-True ($rows.Count -eq 4 -and @($rows|Where-Object {$_ -is [Array]}).Count -eq 0) 'Routine report metadata was nested on Windows PowerShell 5.1.'
    Assert-Throws {Assert-DrillSingleRoutineIdentity 'public.a(),auth.managed_test()'} 'Multiple routine identities were accepted.'
    Assert-Throws {New-DrillRoutineACLPlan $path 'bad' ('b'*40)} 'Invalid routine checkpoint was accepted.'
    [IO.File]::WriteAllText($path,$schema+"`nGRANT EXECUTE ON FUNCTION public.admin_pending_events(),auth.managed_test() TO anon;")
    Assert-Throws {New-DrillRoutineACLPlan $path ('a'*32) ('b'*40)} 'A multi-routine statement escaped source scope.'
    [IO.File]::WriteAllText($path,'CREATE FUNCTION public.admin_pending_events() RETURNS boolean LANGUAGE sql AS ''SELECT false'';')
    Assert-Throws {New-DrillRoutineACLPlan $path ('a'*32) ('b'*40)} 'Missing current administrator archive definition was accepted.'
    Write-Host ('PASS: PowerShell '+$PSVersionTable.PSVersion+'; source-owned routine ACL scope, typed arguments, quoted names, literal isolation, single-identity and checkpoint guards.')
}finally{
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
