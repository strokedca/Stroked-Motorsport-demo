#Requires -Version 5.1
$ErrorActionPreference='Stop'
foreach($name in @('Stroked-Postgres-Restore-Check.ps1','Stroked-Run-Fresh-Backup.ps1')) {
 $tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors.Message -join "`n")}
}
. (Join-Path $PSScriptRoot 'Stroked-Postgres-Restore-Check.ps1')
function Assert-True {param([bool]$Condition,[string]$Message);if(-not $Condition){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('stroked-plan-test-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
 $fixture=@'
-- PostgreSQL database dump
\restrict fixture
SET check_function_bodies = false;
--
-- Name: users; Type: TABLE; Schema: auth; Owner: postgres
--
CREATE TABLE auth.users(id uuid);
--
-- Name: access; Type: POLICY; Schema: auth; Owner: postgres
--
CREATE POLICY access ON auth.users USING (public.fixture());
--
-- Name: users_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--
ALTER TABLE auth.users ADD PRIMARY KEY(id);
-- PostgreSQL database dump complete
\unrestrict fixture
'@
 $p=Join-Path $temp 'fixture.sql';[IO.File]::WriteAllText($p,$fixture)
 $blocks=@(Get-StrokedDumpBlocks $p | Where-Object {$_.Type -ne 'PRELUDE'})
 Assert-True ($blocks.Count -eq 3) 'Schema objects were not split correctly.'
 Assert-True ($blocks[0].Phase -eq 2 -and $blocks[1].Phase -eq 5 -and $blocks[2].Phase -eq 3) 'Post-data dependencies are not ordered.'
 Assert-True (($blocks.Sql -join '') -notmatch '\\(?:un)?restrict') 'Dump session guards were not removed.'
 # Match CLI v3's default: all lines beginning with -- are omitted, including
 # object annotations and the dump footer. The actual SQL remains recoverable.
 $withoutComments=[regex]::Replace($fixture,'(?m)^--[^\r\n]*\r?\n?','')
 [IO.File]::WriteAllText($p,$withoutComments)
 $bare=@(Get-StrokedDumpBlocks $p | Where-Object {$_.Type -ne 'PRELUDE'})
 Assert-True (($bare.Sql -join "`n") -ceq ($blocks.Sql -join "`n")) 'Comment-free CLI SQL changed while planning the restore.'
 [IO.File]::WriteAllText($p,'VACUUM;')
 $threw=$false;try{$null=Get-StrokedDumpBlocks $p}catch{$threw=$true};Assert-True $threw 'Unsupported object was silently accepted.'
 $quoted=@'
/* outer ; /* inner ; */ comment */
CREATE FUNCTION public.quoted_fixture() RETURNS text LANGUAGE plpgsql AS $body$
BEGIN
 -- A routine body can contain SQL-looking text and semicolons.
 RETURN 'CREATE POLICY fake; it''s a literal';
END
$body$;
COMMENT ON FUNCTION public.quoted_fixture() IS E'escaped quote: \' ; remains one value';
CREATE TABLE public."semi;colon"(id int, note text DEFAULT 'line one
line two;');
'@
 $statements=@(Split-StrokedSchemaStatements $quoted)
 Assert-True ($statements.Count -eq 3) 'Quoted or dollar-quoted SQL was split inside its contents.'
 Assert-True ($statements[0].Contains("RETURN 'CREATE POLICY fake; it''s a literal';")) 'Routine body contents changed.'
 foreach($broken in @("CREATE TABLE public.fixture(id int)","SELECT 'unfinished",'CREATE FUNCTION f() RETURNS void AS $broken$ BEGIN;','/* unfinished','\! unsafe-command')) {
  $threw=$false;try{$null=Split-StrokedSchemaStatements $broken}catch{$threw=$true};Assert-True $threw 'Incomplete or unexpected schema input was accepted.'
 }
 $main=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Stroked-Run-Fresh-Backup.ps1'))
 Assert-True ($main -notmatch '(?m)^\s*&.*-UseExistingExports') 'Fresh starter passes the old export switch.'
 foreach($starter in @('CHECK-DATABASE.cmd','BACKUP-NOW.cmd')) {
  $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $starter)).ToLowerInvariant()
  foreach($name in @('Stroked-Database-Backup.ps1','Stroked-Recovery-Check.ps1','Stroked-Files-Backup.ps1','Stroked-Postgres-Restore-Check.ps1','Stroked-Run-Fresh-Backup.ps1','start-isolated-postgres.sh','verify-restored-database.sql')) {
   Assert-True ($text.Contains((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash.ToLowerInvariant())) 'Starter helper checksum is stale.'
  }
 }
 Write-Host 'Restore-plan and fresh-starter checks passed (synthetic inputs only).'
} finally {Remove-Item -LiteralPath $temp -Recurse -Force}
exit 0
