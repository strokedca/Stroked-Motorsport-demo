function Assert-DrillSingleRoutineIdentity([string]$Identity){
    $open=$Identity.IndexOf('(');if($open -lt 1){throw 'Archived routine identity is invalid.'}
    $depth=0;$quoted=$false;$closed=-1
    for($i=$open;$i -lt $Identity.Length;$i++){
        $c=$Identity[$i]
        if($quoted){if($c -eq '"'){if($i+1 -lt $Identity.Length -and $Identity[$i+1] -eq '"'){$i++}else{$quoted=$false}};continue}
        if($c -eq '"'){$quoted=$true;continue}
        if($c -eq '('){$depth++}
        elseif($c -eq ')'){$depth--;if($depth -eq 0){$closed=$i;break}}
    }
    if($quoted -or $closed -lt 0 -or $Identity.Substring($closed+1).Trim()){throw 'Only one archived routine identity may be replayed per ACL statement.'}
}

function New-DrillRoutineACLPlan {
    param([string]$SchemaPath,[string]$RunID,[string]$Commit)
    if($RunID -cnotmatch '^[a-f0-9]{32}$' -or $Commit -cnotmatch '^[a-f0-9]{40}$'){throw 'Routine ACL checkpoint identity is invalid.'}
    $required=@('public.admin_pending_events','public.get_pending_events','public.is_event_admin','public.stroked_live_v55_admin_events')
    $defined=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $empty=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $identities=New-Object 'Collections.Generic.List[string]'
    $statements=New-Object 'Collections.Generic.List[string]'
    $identifier='(?:"(?<s>[a-z_][a-z0-9_]*)"|(?<s>[a-z_][a-z0-9_]*))\s*\.\s*(?:"(?<f>[a-z_][a-z0-9_]*)"|(?<f>[a-z_][a-z0-9_]*))'
    $blocks=@(Get-StrokedDumpBlocks $SchemaPath)
    foreach($block in $blocks){
        $m=[regex]::Match($block.Sql,'(?is)^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+'+$identifier+'\s*\(')
        if(-not $m.Success -or -not (Test-DrillApplicationSchema $m.Groups['s'].Value)){continue}
        $name=$m.Groups['s'].Value+'.'+$m.Groups['f'].Value
        $null=$defined.Add($name)
        if($block.Sql.Substring($m.Length) -match '^\s*\)'){$null=$empty.Add($name)}
    }
    foreach($name in $required){
        if(-not $empty.Contains($name)){throw 'Required administrator routine definition is missing from the archive.'}
        $identity=$name+'()';$null=$seen.Add($identity);$identities.Add($identity)
    }
    foreach($block in $blocks){
        if($block.Type -cne 'ACL OR COMMENT'){continue}
        $m=[regex]::Match($block.Sql,'(?is)^(?:GRANT|REVOKE)\b.+?\bON\s+FUNCTION\s+(?<identity>'+$identifier+'\s*\(.*\))\s+(?:TO|FROM)\s+')
        if(-not $m.Success){continue}
        $name=$m.Groups['s'].Value+'.'+$m.Groups['f'].Value
        if(-not $defined.Contains($name)){continue}
        $identity=$m.Groups['identity'].Value.Trim()
        Assert-DrillSingleRoutineIdentity $identity
        if($seen.Add($identity)){$identities.Add($identity)}
        $statements.Add($block.Sql)
    }
    $sql=New-Object Text.StringBuilder
    $null=$sql.AppendLine("BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='30s';")
    $null=$sql.AppendLine('DO $rpc_checkpoint$ BEGIN IF NOT EXISTS(SELECT 1 FROM stroked_recovery_drill.marker WHERE run_id='''+$RunID+''' AND source_commit='''+$Commit+''') THEN RAISE EXCEPTION ''Routine ACL checkpoint differs'' USING ERRCODE=''PDB09''; END IF; END $rpc_checkpoint$;')
    foreach($identity in $identities){
        # Restore PostgreSQL's baseline PUBLIC EXECUTE, then replay the dump's
        # explicit restrictions. Extra Supabase anon/authenticated defaults are
        # removed; private functions' archived PUBLIC revokes remain required.
        $null=$sql.AppendLine('REVOKE ALL PRIVILEGES ON FUNCTION '+$identity+' FROM PUBLIC,anon,authenticated;')
        $null=$sql.AppendLine('GRANT EXECUTE ON FUNCTION '+$identity+' TO PUBLIC;')
    }
    foreach($statement in $statements){$null=$sql.AppendLine($statement)}
    $null=$sql.AppendLine(@'
DO $rpc_protection$ BEGIN
 IF EXISTS(SELECT 1 FROM (VALUES ('public.admin_pending_events()'),('public.get_pending_events()'),('public.is_event_admin()')) f(signature)
  WHERE has_function_privilege('anon',signature,'EXECUTE') OR has_function_privilege('authenticated',signature,'EXECUTE') OR
    NOT has_function_privilege('service_role',signature,'EXECUTE')) THEN
  RAISE EXCEPTION 'STROKED_DRILL_CHECK_DBP05' USING ERRCODE='PDB05';
 END IF;
 IF NOT has_function_privilege('authenticated','public.stroked_live_v55_admin_events()','EXECUTE') THEN
  RAISE EXCEPTION 'STROKED_DRILL_CHECK_DBP06' USING ERRCODE='PDB06';
 END IF;
END $rpc_protection$;
NOTIFY pgrst,'reload schema'; COMMIT;
'@)
    return [pscustomobject]@{SQL=$sql.ToString();IdentityCount=$identities.Count;StatementCount=$statements.Count}
}

function Read-DrillCoreRoutineGrants {
    $sql=@'
BEGIN READ ONLY;
SELECT json_agg(json_build_object('Signature',signature,'AnonExecute',has_function_privilege('anon',signature,'EXECUTE'),'AuthenticatedExecute',has_function_privilege('authenticated',signature,'EXECUTE'),'ServiceExecute',has_function_privilege('service_role',signature,'EXECUTE')) ORDER BY signature)
FROM (VALUES ('public.admin_pending_events()'),('public.get_pending_events()'),('public.is_event_admin()'),('public.stroked_live_v55_admin_events()')) f(signature);
COMMIT;
'@
    $decoded=ConvertFrom-Json -InputObject ('{"Rows":'+(Invoke-DrillSQL $sql 'supabase_admin').Trim()+'}')
    foreach($row in $decoded.Rows){$row}
}
