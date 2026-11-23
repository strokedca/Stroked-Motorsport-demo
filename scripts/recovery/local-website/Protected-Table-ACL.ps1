function New-DrillProtectedTableACLPlan {
    param([string]$SchemaPath,[string]$RunID,[string]$Commit)
    if($RunID -cnotmatch '^[a-f0-9]{32}$' -or $Commit -cnotmatch '^[a-f0-9]{40}$'){throw 'Protected-table ACL checkpoint identity is invalid.'}
    $targets=@('public.events','stroked_live_v55.admin_security')
    $definitions=@{};$statements=New-Object 'Collections.Generic.List[string]'
    $identifier='(?:"(?<s>[a-z_][a-z0-9_]*)"|(?<s>[a-z_][a-z0-9_]*))\s*\.\s*(?:"(?<t>[a-z_][a-z0-9_]*)"|(?<t>[a-z_][a-z0-9_]*))'
    foreach($block in @(Get-StrokedDumpBlocks $SchemaPath)){
        $definition=[regex]::Match($block.Sql,'(?is)^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'+$identifier+'\s*\(')
        if($definition.Success){
            $name=$definition.Groups['s'].Value+'.'+$definition.Groups['t'].Value
            if($name -cin $targets){if($definitions.ContainsKey($name)){throw 'Protected table has duplicate archive definitions.'};$definitions[$name]=$true}
        }
        if($block.Type -cne 'ACL OR COMMENT' -or $block.Sql -notmatch '(?i)^(?:GRANT|REVOKE)\b'){continue}
        $acl=[regex]::Match($block.Sql,'(?is)^(?:GRANT|REVOKE)\b.+?\bON\s+(?:TABLE\s+)?'+$identifier+'\s+(?:TO|FROM)\s+')
        if($acl.Success){
            $name=$acl.Groups['s'].Value+'.'+$acl.Groups['t'].Value
            if($name -cin $targets){$statements.Add($block.Sql)}
        }elseif($block.Sql -notmatch '(?i)\bON\s+(?:FUNCTION|PROCEDURE|ROUTINE|SEQUENCE|SCHEMA|TYPE|DOMAIN|DATABASE|TABLESPACE|LANGUAGE|FOREIGN|LARGE|PARAMETER)\b' -and $block.Sql -match '(?is)\bON\s+(?:TABLE\s+)?[^;]*(?:"?public"?\s*\.\s*"?events"?|"?stroked_live_v55"?\s*\.\s*"?admin_security"?)'){
            throw 'Protected-table ACL syntax requires review.'
        }
    }
    foreach($name in $targets){if(-not $definitions.ContainsKey($name)){throw 'Protected-table archive definition is missing.'}}
    $sql=New-Object Text.StringBuilder
    $null=$sql.AppendLine("BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='30s';")
    $null=$sql.AppendLine('DO $acl_checkpoint$ BEGIN IF NOT EXISTS(SELECT 1 FROM stroked_recovery_drill.marker WHERE run_id='''+$RunID+''' AND source_commit='''+$Commit+''') THEN RAISE EXCEPTION ''Protected ACL checkpoint differs'' USING ERRCODE=''PDB09''; END IF; END $acl_checkpoint$;')
    $null=$sql.AppendLine('LOCK TABLE public.events,stroked_live_v55.admin_security IN ACCESS EXCLUSIVE MODE;')
    # A plain pg_dump table GRANT describes the source ACL; it does not remove
    # extra privileges inherited from local Supabase creation defaults.
    # Reset only browser-role table grants on these two archive-defined tables.
    $null=$sql.AppendLine('REVOKE ALL PRIVILEGES ON TABLE public.events,stroked_live_v55.admin_security FROM PUBLIC,anon,authenticated;')
    foreach($statement in $statements){$null=$sql.AppendLine($statement)}
    $null=$sql.AppendLine(@'
DO $acl_protection$ BEGIN
 IF has_table_privilege('anon','stroked_live_v55.admin_security','SELECT') OR
    has_table_privilege('authenticated','stroked_live_v55.admin_security','SELECT') OR
    has_table_privilege('anon','public.events','SELECT') OR
    has_table_privilege('authenticated','public.events','SELECT') THEN
  RAISE EXCEPTION 'STROKED_DRILL_CHECK_DBP04' USING ERRCODE='PDB04';
 END IF;
END $acl_protection$;
NOTIFY pgrst,'reload schema'; COMMIT;
'@)
    return [pscustomobject]@{SQL=$sql.ToString();Tables=$targets;StatementCount=$statements.Count}
}

function Read-DrillProtectedTableGrants {
    $sql=@'
BEGIN READ ONLY;
SELECT json_build_object(
 'AdminSecurityAnonSelect',has_table_privilege('anon','stroked_live_v55.admin_security','SELECT'),
 'AdminSecurityAuthenticatedSelect',has_table_privilege('authenticated','stroked_live_v55.admin_security','SELECT'),
 'LegacyEventsAnonSelect',has_table_privilege('anon','public.events','SELECT'),
 'LegacyEventsAuthenticatedSelect',has_table_privilege('authenticated','public.events','SELECT'));
COMMIT;
'@
    return ConvertFrom-Json -InputObject (Invoke-DrillSQL $sql 'supabase_admin').Trim()
}
