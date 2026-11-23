# Disposable PostgreSQL fixture; contains no owner data and publishes no ports.
[CmdletBinding()]
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Local-Core.ps1')
. (Join-Path $Package 'Schema-Parser.ps1')
. (Join-Path $Package 'Protected-Table-ACL.ps1')
$docker=(Get-Command docker -CommandType Application | Select-Object -First 1).Source
$fixture='stroked-protection-ci-'+[guid]::NewGuid().ToString('N')
$endpoint='unix:///var/run/docker.sock'
$sourceFolder=Join-Path ([IO.Path]::GetTempPath()) ('stroked-archive-acl-ci-'+[guid]::NewGuid().ToString('N'))
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
    # Reproduce a real schema dump restored into broader creation defaults.
    # The source permits several write privileges, but deliberately no SELECT.
    $null=Run-SQL 'GRANT INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON TABLE public.events TO anon,authenticated; GRANT ALL ON TABLE public.events TO service_role;'
    $dump=Invoke-QuietNative $docker @('--host',$endpoint,'exec',$fixture,'pg_dump','-h','127.0.0.1','-U','postgres','-d','postgres','--schema-only','--no-owner','--table=public.events') 60
    $null=Run-SQL 'DROP TABLE public.events; ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated;'
    $null=Run-SQL $dump
    $broader=(Run-SQL "SELECT has_table_privilege('anon','public.events','SELECT') AND has_table_privilege('authenticated','public.events','SELECT');").Trim()
    if($broader -cne 't'){throw 'Default-privilege restore mismatch did not reproduce.'}
    $failed=$false;try{$null=Run-SQL $verify}catch{$failed=$true}
    if(-not $failed -or $script:LastNativeFailure.SafeCheckID -cne 'DBP04'){throw 'Real dump/default-grant mismatch did not reproduce DBP04.'}
    Write-Host 'REPRODUCED: real pg_dump table ACL replay retains extra local creation-default SELECT grants and fails DBP04.'
    $null=Run-SQL ("CREATE SCHEMA stroked_recovery_drill; CREATE TABLE stroked_recovery_drill.marker(run_id text,source_commit text); INSERT INTO stroked_recovery_drill.marker VALUES ('"+('a'*32)+"','"+('b'*40)+"'); INSERT INTO public.events VALUES(7);")
    $null=New-Item -ItemType Directory -Path $sourceFolder
    $schemaPath=Join-Path $sourceFolder 'schema.sql'
    $protectedReference="`nCREATE TABLE stroked_live_v55.admin_security(user_id uuid);`nGRANT ALL ON TABLE stroked_live_v55.admin_security TO service_role;"
    [IO.File]::WriteAllText($schemaPath,$dump+$protectedReference,(New-Object Text.UTF8Encoding($false)))
    $aclPlan=New-DrillProtectedTableACLPlan $schemaPath ('a'*32) ('b'*40)
    $wrong=New-DrillProtectedTableACLPlan $schemaPath ('c'*32) ('b'*40)
    $failed=$false;try{$null=Run-SQL $wrong.SQL}catch{$failed=$true}
    if(-not $failed -or $script:LastSQLState -cne 'PDB09' -or (Run-SQL "SELECT has_table_privilege('anon','public.events','SELECT');").Trim() -cne 't'){throw 'Foreign checkpoint guard did not refuse before ACL mutation.'}
    $null=Run-SQL $aclPlan.SQL
    $null=Run-SQL $verify
    $null=Run-SQL $aclPlan.SQL
    $preserved=(Run-SQL "SELECT (NOT has_table_privilege('anon','public.events','SELECT')) AND (NOT has_table_privilege('authenticated','public.events','SELECT')) AND has_table_privilege('anon','public.events','INSERT') AND has_table_privilege('authenticated','public.events','UPDATE') AND has_table_privilege('service_role','public.events','SELECT') AND (SELECT count(*)=1 FROM public.events WHERE id=7) AND (SELECT count(*)=1 FROM auth.mfa_factors);").Trim()
    if($preserved -cne 't'){throw 'Archived permissions, service access or data were not preserved.'}
    [IO.File]::WriteAllText($schemaPath,$dump+$protectedReference+"`nGRANT SELECT ON TABLE public.events TO anon;",(New-Object Text.UTF8Encoding($false)))
    $bad=New-DrillProtectedTableACLPlan $schemaPath ('a'*32) ('b'*40)
    $failed=$false;try{$null=Run-SQL $bad.SQL}catch{$failed=$true}
    if(-not $failed -or $script:LastNativeFailure.SafeCheckID -cne 'DBP04' -or (Run-SQL "SELECT has_table_privilege('anon','public.events','SELECT');").Trim() -cne 'f'){throw 'Permissive archived ACL did not fail and roll back.'}
    $null=Run-SQL $verify
    Write-Host 'PASS: real dump ACL repair, idempotent resume, archived partial grants, service access, data/MFA preservation, foreign-checkpoint refusal and bad-archive rollback.'
    Write-Host 'PASS: baseline protection verifier and all eight isolated failure paths; fixed identifiers only, no owner records.'
}finally{
    & $docker --host $endpoint rm -f -v $fixture > $null 2>&1
    if(Test-Path -LiteralPath $sourceFolder){Remove-Item -LiteralPath $sourceFolder -Recurse -Force}
}
