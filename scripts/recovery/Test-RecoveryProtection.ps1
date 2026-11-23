# Disposable PostgreSQL fixture; contains no owner data and publishes no ports.
[CmdletBinding()]
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Local-Core.ps1')
$docker=(Get-Command docker -CommandType Application | Select-Object -First 1).Source
$fixture='stroked-protection-ci-'+[guid]::NewGuid().ToString('N')
$endpoint='unix:///var/run/docker.sock'
function Run-SQL([string]$SQL){
    Invoke-QuietNative $docker @('--host',$endpoint,'exec','-i',$fixture,'psql','-h','127.0.0.1','-U','postgres','-d','postgres','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate') 60 ($SQL+"`n")
}
try{
    & $docker --host $endpoint run -d --name $fixture --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine > $null
    if($LASTEXITCODE -ne 0){throw 'Could not create disposable PostgreSQL fixture.'}
    $ready=$false
    for($i=0;$i -lt 50;$i++){
        & $docker --host $endpoint exec $fixture pg_isready -h 127.0.0.1 -U postgres > $null 2>&1
        if($LASTEXITCODE -eq 0){$ready=$true;break}
        Start-Sleep -Seconds 1
    }
    if(-not $ready){throw 'Disposable PostgreSQL fixture was not ready.'}
    $setup=@'
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA stroked_live_v55;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email_confirmed_at timestamptz);
CREATE TABLE auth.mfa_factors(user_id uuid,status text,factor_type text);
CREATE TABLE stroked_live_v55.admin_security(user_id uuid);
CREATE TABLE stroked_live_v55.member_blocks(user_id uuid);
CREATE TABLE public.event_admins(user_id uuid);
CREATE TABLE public.events(id int);
ALTER TABLE stroked_live_v55.admin_security ENABLE ROW LEVEL SECURITY;
ALTER TABLE stroked_live_v55.member_blocks ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.admin_pending_events() RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION public.get_pending_events() RETURNS boolean LANGUAGE sql AS 'SELECT false';
CREATE FUNCTION public.is_event_admin() RETURNS boolean LANGUAGE sql AS 'SELECT false';
REVOKE ALL ON FUNCTION public.admin_pending_events(),public.get_pending_events(),public.is_event_admin() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_pending_events(),public.get_pending_events(),public.is_event_admin() TO service_role;
CREATE FUNCTION public.stroked_live_v55_admin_events() RETURNS boolean LANGUAGE sql AS 'SELECT false';
REVOKE ALL ON FUNCTION public.stroked_live_v55_admin_events() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stroked_live_v55_admin_events() TO authenticated;
CREATE FUNCTION stroked_live_v55.is_admin() RETURNS boolean LANGUAGE sql AS $$SELECT coalesce((current_setting('request.jwt.claims',true)::jsonb->>'aal')='aal2',false)$$;
INSERT INTO auth.users VALUES('00000000-0000-0000-0000-000000000001',now());
INSERT INTO auth.mfa_factors VALUES('00000000-0000-0000-0000-000000000001','verified','totp');
INSERT INTO stroked_live_v55.admin_security VALUES('00000000-0000-0000-0000-000000000001');
INSERT INTO public.event_admins VALUES('00000000-0000-0000-0000-000000000001');
'@
    $null=Run-SQL $setup
    $verify=[IO.File]::ReadAllText((Join-Path $Package 'verify-core.sql'))
    $null=Run-SQL $verify
    $mutations=@(
        'DELETE FROM stroked_live_v55.admin_security;',
        'DELETE FROM auth.mfa_factors;',
        'ALTER TABLE stroked_live_v55.admin_security DISABLE ROW LEVEL SECURITY;',
        'GRANT SELECT ON public.events TO anon;',
        'GRANT EXECUTE ON FUNCTION public.admin_pending_events() TO anon;',
        'REVOKE EXECUTE ON FUNCTION public.stroked_live_v55_admin_events() FROM authenticated;',
        "CREATE OR REPLACE FUNCTION stroked_live_v55.is_admin() RETURNS boolean LANGUAGE sql AS 'SELECT true';",
        "CREATE OR REPLACE FUNCTION stroked_live_v55.is_admin() RETURNS boolean LANGUAGE sql AS 'SELECT false';"
    )
    for($i=0;$i -lt $mutations.Count;$i++){
        $failed=$false
        try{$null=Run-SQL ("BEGIN;`n"+$mutations[$i]+"`n"+$verify+"`nROLLBACK;")}catch{$failed=$true}
        $code='PDB{0:00}' -f ($i+1);$safe='DBP{0:00}' -f ($i+1)
        if(-not $failed -or $script:LastSQLState -cne $code -or $script:LastNativeFailure.SafeCheckID -cne $safe -or $script:LastNativeFailure.ExitCode -ne 3){throw ('Protection failure did not reach the safe report as '+$safe)}
        Write-Host ('PASS: real PostgreSQL sqlstate-only verifier failure '+$safe)
    }
    $null=Run-SQL $verify
    Write-Host 'PASS: baseline protection verifier and all eight isolated failure paths; fixed identifiers only, no owner records.'
}finally{
    & $docker --host $endpoint rm -f -v $fixture > $null 2>&1
}
