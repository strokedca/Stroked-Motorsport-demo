#Requires -Version 5.1
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Schema-Parser.ps1')
. (Join-Path $Package 'Protected-Table-ACL.ps1')
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Throws([scriptblock]$Action,[string]$Message){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert-True $failed $Message}
$root=Join-Path ([IO.Path]::GetTempPath()) ('stroked-acl-plan-'+[guid]::NewGuid().ToString('N'))
try{
    $null=New-Item -ItemType Directory -Path $root
    $path=Join-Path $root 'schema.sql'
    $schema=@'
CREATE TABLE public.events(id integer);
CREATE TABLE "stroked_live_v55"."admin_security"(user_id uuid);
GRANT INSERT, UPDATE ON TABLE "public"."events" TO anon,authenticated;
GRANT ALL ON TABLE stroked_live_v55.admin_security TO service_role;
REVOKE ALL ON TABLE stroked_live_v55.admin_security FROM PUBLIC;
GRANT SELECT ON TABLE public.unrelated TO anon;
GRANT EXECUTE ON FUNCTION public.events() TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon;
CREATE FUNCTION public.test_literal() RETURNS text LANGUAGE sql AS $$SELECT 'GRANT SELECT ON TABLE public.events TO anon;'$$;
'@
    [IO.File]::WriteAllText($path,$schema,(New-Object Text.UTF8Encoding($false)))
    $plan=New-DrillProtectedTableACLPlan $path ('a'*32) ('b'*40)
    Assert-True ($plan.StatementCount -eq 3) 'The ACL plan did not select exactly the three archive table statements.'
    Assert-True ($plan.SQL -notmatch 'unrelated|ON FUNCTION|DEFAULT PRIVILEGES|CREATE FUNCTION') 'The ACL plan replayed an unrelated object or routine body.'
    Assert-True ($plan.SQL -match 'REVOKE ALL PRIVILEGES ON TABLE public.events,stroked_live_v55.admin_security FROM PUBLIC,anon,authenticated') 'Local browser grants were not reset on exactly the protected tables.'
    Assert-True ($plan.SQL -match 'stroked_recovery_drill.marker' -and $plan.SQL -match 'PDB04' -and $plan.SQL -match 'PDB09') 'Checkpoint or post-replay protection guard is missing.'
    Assert-Throws {New-DrillProtectedTableACLPlan $path 'bad-run' ('b'*40)} 'Invalid checkpoint ID was accepted.'
    [IO.File]::WriteAllText($path,'CREATE TABLE public.events(id integer);')
    Assert-Throws {New-DrillProtectedTableACLPlan $path ('a'*32) ('b'*40)} 'A missing protected archive table was accepted.'
    [IO.File]::WriteAllText($path,$schema+"`nGRANT SELECT ON TABLE public.events,public.unrelated TO anon;")
    Assert-Throws {New-DrillProtectedTableACLPlan $path ('a'*32) ('b'*40)} 'A multiple-table ACL outside the exact scope was accepted.'
    Write-Host ('PASS: PowerShell '+$PSVersionTable.PSVersion+'; exact archive table ACL scope, quoted identifiers, routine-body isolation and checkpoint guards.')
}finally{
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
