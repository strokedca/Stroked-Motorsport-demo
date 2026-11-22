# Plans a single-transaction import into an EMPTY local managed Supabase database.
# Managed DDL, role/password dumps, Vault secrets, schedules and old sessions are not replayed.
function Test-DrillApplicationSchema([string]$Schema) {
    return $Schema -ceq 'public' -or $Schema -cmatch '^stroked_(?:live_v55|v55_testing|promotions|payments|alerts)$'
}
function Test-DrillCopyTable([string]$Schema,[string]$Table) {
    if(Test-DrillApplicationSchema $Schema){return $true}
    if($Schema -ceq 'storage'){return $Table -cin @('buckets','objects')}
    if($Schema -ceq 'auth'){
        return $Table -cin @('users','identities','mfa_factors','mfa_recovery_code_sets','mfa_recovery_codes')
    }
    return $false
}
function New-DrillDataPlan([string]$InputPath,[string]$OutputPath,$Manifest) {
    $reader=[IO.File]::OpenText($InputPath)
    $writer=New-Object IO.StreamWriter($OutputPath,$false,(New-Object Text.UTF8Encoding($false)))
    $counts=[ordered]@{};$skipped=New-Object 'Collections.Generic.List[string]'
    $seq=New-Object 'Collections.Generic.List[string]'
    $current=$null;$selected=$false;$all=@{};$columns=@{};$lineNumber=0
    $script:LastDataExportIssue=$null
    try {
        while($null -ne ($line=$reader.ReadLine())) {
            $lineNumber++
            if($null -ne $current){
                if($selected){$writer.WriteLine($line)}
                if($line -ceq '\.'){$current=$null;$selected=$false}
                else{$all[$current]=[long]$all[$current]+1;if($selected){$counts[$current]=[long]$counts[$current]+1}}
                continue
            }
            if($line -cmatch '^COPY (?<s>"?[a-z_][a-z0-9_]*"?)\.(?<t>"?[a-z_][a-z0-9_]*"?) \((?<cols>[^\r\n]+)\) FROM stdin;\s*$'){
                $schema=$Matches.s.Trim('"');$table=$Matches.t.Trim('"');$columnText=$Matches.cols
                $current=$schema+'.'+$table
                if($all.ContainsKey($current)){throw 'Duplicate COPY table in the backup.'}
                $all[$current]=[long]0
                $columns[$current]=@(foreach($c in ($columnText -split ',')){$id=$c.Trim().Trim('"');if($id -cnotmatch '^[a-z_][a-z0-9_]*$'){throw 'Unsupported COPY column identifier.'};$id})
                $selected=Test-DrillCopyTable $schema $table
                if($selected){$counts[$current]=[long]0;$writer.WriteLine($line)}else{$skipped.Add($current)}
                continue
            }
            # The CLI requests --quote-all-identifier, including names inside
            # setval's regclass string. Accept balanced quoted/simple identifiers.
            if($line -cmatch '^SELECT (?:pg_catalog\.)?setval\(''(?<schema>(?:"[a-z_][a-z0-9_]*"|[a-z_][a-z0-9_]*))\.(?<seq>(?:"[a-z_][a-z0-9_]*"|[a-z_][a-z0-9_]*))'', (?<n>-?[0-9]+), (?<called>true|false)\);\s*$'){
                if(Test-DrillApplicationSchema ($Matches.schema.Trim('"'))){$seq.Add($line)};continue
            }
            # The CLI appends this trailer. The enclosing import owns session
            # settings and transaction boundaries, so do not replay RESET ALL.
            if($line -cmatch '^RESET ALL;\s*$'){continue}
            if(-not $line.Trim() -or $line.StartsWith('--') -or $line -cmatch '^SET [a-z_][a-z0-9_]*\s*=' -or
               $line -cmatch '^SELECT (?:pg_catalog\.)?set_config\(' -or $line -cmatch '^\\(?:un)?restrict\s+[A-Za-z0-9]+\s*$'){continue}
            $kind='OtherSQL'
            if($line -cmatch '^SELECT (?:pg_catalog\.)?setval\('){$kind='SequenceReset'}
            elseif($line -cmatch '^RESET '){$kind='SessionReset'}
            elseif($line -cmatch '^COPY '){$kind='CopyHeader'}
            elseif($line.StartsWith('\')){$kind='MetaCommand'}
            $script:LastDataExportIssue=[pscustomobject]@{LineNumber=$lineNumber;StatementKind=$kind}
            throw 'Unsupported non-COPY statement in the data export.'
        }
        if($null -ne $current){throw 'Incomplete COPY block in the data export.'}
        foreach($name in $all.Keys){
            $property=$Manifest.copyTableRowCounts.PSObject.Properties[$name]
            if($null -eq $property -or [long]$property.Value -ne [long]$all[$name]){throw 'A backup row count differs from its manifest.'}
        }
        foreach($name in @('auth.users','auth.identities','auth.mfa_factors','public.event_admins','public.stroked_v5_events','stroked_live_v55.admin_security')){
            if(-not $counts.Contains($name)){throw 'The core account, event or MFA recovery table is missing.'}
        }
        foreach($statement in $seq){$writer.WriteLine($statement)}
        # Invalidate pending local test tokens without changing IDs, password hashes or MFA.
        $clear=@('confirmation_token','recovery_token','email_change_token_new','email_change_token_current','phone_change_token','reauthentication_token')
        $assignments=@(foreach($col in $clear){if($col -cin $columns['auth.users']){$col+" = ''"}})
        if($assignments.Count){$writer.WriteLine('UPDATE auth.users SET '+($assignments -join ', ')+';')}
    } finally{$reader.Dispose();$writer.Dispose()}
    return [pscustomobject]@{Counts=$counts;Skipped=@($skipped.ToArray());Columns=$columns;TablesInPrimaryData=$all.Count}
}
function New-DrillImportPlan([string]$Payload,$Manifest,[string]$RunID,[string]$Commit,[string]$OutputFolder) {
    if($RunID -cnotmatch '^[a-f0-9]{32}$' -or $Commit -cnotmatch '^[a-f0-9]{40}$'){throw 'Recovery checkpoint identity is invalid.'}
    $blocks=@(Get-StrokedDumpBlocks (Join-Path $Payload 'schema.sql'))
    $retained=New-Object 'Collections.Generic.List[object]'
    $excluded=New-Object 'Collections.Generic.List[string]'
    foreach($block in $blocks){
        $sql=$block.Sql
        if($block.Type -ceq 'SCHEMA'){
            if($sql -cnotmatch '^CREATE SCHEMA IF NOT EXISTS "?(?<s>[a-z_][a-z0-9_]*)"?\s*;'){throw 'Unexpected schema declaration format.'}
            if(-not (Test-DrillApplicationSchema $Matches.s)){throw 'Managed or unknown schema DDL appeared in the application export.'}
        }
        if($block.Type -ceq 'EXTENSION'){
            if($sql -cnotmatch '^CREATE EXTENSION(?: IF NOT EXISTS)? "?(?<e>[a-z0-9_-]+)"?(?:\s|;)'){throw 'Unexpected extension declaration.'}
            if($Matches.e -cin @('pg_cron','pg_net','supabase_vault')){$excluded.Add('Managed extension declaration: '+$Matches.e);continue}
            if($Matches.e -cnotin @('uuid-ossp','pgcrypto','pg_stat_statements','pg_graphql','pg_jsonschema','moddatetime','citext','unaccent','vector','pg_trgm','pgjwt')){throw 'An additional extension requires review.'}
        }
        if($sql -match '^(?i:COMMENT ON EXTENSION)\s+"?(?:pg_cron|pg_net|supabase_vault)"?\s'){$excluded.Add('Managed extension comment');continue}
        if($sql -match '^(?i:CREATE PUBLICATION|ALTER PUBLICATION)\b'){$excluded.Add('Publication configuration preserved locally');continue}
        if($block.Type -ceq 'POLICY OR TRIGGER' -and $sql -match '^(?i:CREATE .*TRIGGER)\b' -and $sql -match '(?i)"?supabase_functions"?\s*\.\s*"?http_request"?'){$excluded.Add('Outbound database webhook trigger');continue}
        # Managed table/function DDL belongs to the current local services, not the dump.
        if($sql -match '^(?i:CREATE|ALTER)\s+(?:OR REPLACE\s+)?(?:TABLE|TYPE|DOMAIN|FUNCTION|PROCEDURE|SEQUENCE|VIEW)\s+(?:IF NOT EXISTS\s+)?"?(?:auth|storage|vault|cron|net|supabase_functions|supabase_migrations)"?\.'){
            throw 'Managed schema modification appeared in the application export.'
        }
        $retained.Add($block)
    }
    # Restore project-owned storage policies, preserving all current managed tables/roles.
    foreach($block in @(Get-StrokedDumpBlocks (Join-Path $Payload 'managed-schema-reference.sql'))){
        if($block.Sql -match '^(?i:CREATE POLICY)\s+"?stroked_[a-z0-9_]+"?\s+(?i:ON)\s+"?storage"?\."?objects"?\s'){$retained.Add($block)}
        elseif($block.Sql -match '^(?i:CREATE .*TRIGGER)\b' -and $block.Sql -match '(?i)\bON\s+"?auth"?\."?users"?\b'){
            if($block.Sql -match '(?i)EXECUTE (?:FUNCTION|PROCEDURE)\s+"?(?:public|stroked_[a-z0-9_]+)"?\.'){$retained.Add($block)}
            else{throw 'An Auth trigger requires a managed-schema review.'}
        }
    }
    $unique=New-Object 'Collections.Generic.List[object]'
    $seen=@{}
    foreach($block in $retained){
        if($seen.ContainsKey($block.Key)){if($seen[$block.Key] -cne $block.Sql){throw 'Overlapping schema definitions differ.'};continue}
        $seen[$block.Key]=$block.Sql;$unique.Add($block)
    }
    $retained=$unique
    $data=New-DrillDataPlan (Join-Path $Payload 'data.sql') (Join-Path $OutputFolder 'selected-data.sql') $Manifest
    $text=New-Object Text.StringBuilder
    $null=$text.AppendLine('\set ON_ERROR_STOP on')
    $null=$text.AppendLine('BEGIN; SET check_function_bodies=false; SET session_replication_role=replica;')
    $schemaText=($retained.ToArray().Sql -join "`n")
    $compatibilityRoles=@(foreach($role in @('cli_login_postgres','supabase_etl_admin','supabase_read_only_user','dashboard_user','pgbouncer')){
        if($schemaText -match ('(?<![a-z0-9_])'+$role+'(?![a-z0-9_])')){$role}
    })
    if($compatibilityRoles.Count){
        $list=(@($compatibilityRoles | ForEach-Object {"'"+$_+"'"}) -join ',')
        $null=$text.AppendLine('DO $local_roles$ DECLARE r text; BEGIN FOREACH r IN ARRAY ARRAY['+$list+'] LOOP IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format(''CREATE ROLE %I NOLOGIN NOINHERIT'',r); END IF; END LOOP; END $local_roles$;')
    }

    $null=$text.AppendLine('CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions; CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;')
    foreach($phase in 0..2){foreach($block in @($retained.ToArray() | Where-Object {$_.Phase -eq $phase})){$null=$text.AppendLine($block.Sql)}}
    $null=$text.AppendLine('\i /tmp/stroked-drill-sql/selected-data.sql')
    $null=$text.AppendLine('SET session_replication_role=origin;')
    foreach($phase in 3..6){foreach($block in @($retained.ToArray() | Where-Object {$_.Phase -eq $phase})){$null=$text.AppendLine($block.Sql)}}
    $null=$text.AppendLine('DO $counts$ BEGIN')
    foreach($name in $data.Counts.Keys){
        if($name -cnotmatch '^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$'){throw 'Unsupported table count identifier.'}
        $parts=$name.Split('.');$q='"'+$parts[0]+'"."'+$parts[1]+'"'
        $null=$text.AppendLine(('IF (SELECT count(*) FROM {0}) <> {1} THEN RAISE EXCEPTION ''Core restore count mismatch''; END IF;' -f $q,$data.Counts[$name]))
    }
    $null=$text.AppendLine('END $counts$;')
    $null=$text.AppendLine("CREATE SCHEMA stroked_recovery_drill; REVOKE ALL ON SCHEMA stroked_recovery_drill FROM PUBLIC; CREATE TABLE stroked_recovery_drill.marker(run_id text PRIMARY KEY, source_commit text NOT NULL, completed_at timestamptz NOT NULL DEFAULT now()); REVOKE ALL ON stroked_recovery_drill.marker FROM PUBLIC; INSERT INTO stroked_recovery_drill.marker(run_id,source_commit) VALUES ('$RunID','$Commit');")
    $null=$text.AppendLine('NOTIFY pgrst, ''reload schema''; COMMIT;')
    [IO.File]::WriteAllText((Join-Path $OutputFolder 'import.sql'),$text.ToString(),(New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{Data=$data;ExcludedDDL=@($excluded.ToArray());TablesCompared=$data.Counts.Count;RoleDumpReplayed=$false;ManagedSchemaDefinitionsReplayed=$false;CompatibilityRoleReferences=$compatibilityRoles}
}
