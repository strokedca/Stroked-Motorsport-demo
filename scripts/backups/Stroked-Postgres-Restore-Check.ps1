#Requires -Version 5.1
<# Offline PostgreSQL drill. Never connects to the hosted database. #>
[CmdletBinding()]
param([string]$RestoreBackupFolder = '', [string]$RestoreHelperFolder = '')

function Get-StrokedDumpBlocks {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    # Modern pg_dump restrict guards are per psql session. This locally generated
    # script is made only from previously decrypted, manifest-verified inputs.
    $text = [regex]::Replace($text, '(?m)^\\(?:un)?restrict[^\n]*\n?', '')
    if ($text -match '(?m)^\\') { throw 'Unexpected psql command in a schema export.' }
    $headers = [regex]::Matches($text, '(?m)^--\n-- Name: (?<name>.*?); Type: (?<type>[^;]+); Schema: (?<schema>.*?); Owner: (?<owner>[^\n]*)\n--\n')
    if ($headers.Count -lt 1 -or $text -notmatch '(?m)^-- PostgreSQL database dump complete\s*$') {
        throw 'A schema reference has an unsupported or incomplete dump format.'
    }
    # Preambles contain SET statements; retain each before its own objects.
    $prelude = $text.Substring(0, $headers[0].Index)
    $result = New-Object 'System.Collections.Generic.List[object]'
    for ($i=0; $i -lt $headers.Count; $i++) {
        $h=$headers[$i]; $end=$text.Length
        if ($i+1 -lt $headers.Count) { $end=$headers[$i+1].Index }
        $type=$h.Groups['type'].Value
        $phase=2
        switch -Regex ($type) {
            '^SCHEMA$' { $phase=0; break }
            '^EXTENSION$' { $phase=1; break }
            '^(CONSTRAINT|INDEX|INDEX ATTACH|TABLE ATTACH|STATISTICS)$' { $phase=3; break }
            '^FK CONSTRAINT$' { $phase=4; break }
            '^(TRIGGER|EVENT TRIGGER|POLICY|ROW SECURITY|RULE)$' { $phase=5; break }
            '^(ACL|DEFAULT ACL|COMMENT|SECURITY LABEL)$' { $phase=6; break }
            '^(TYPE|DOMAIN|FUNCTION|PROCEDURE|AGGREGATE|OPERATOR|OPERATOR CLASS|OPERATOR FAMILY|CAST|COLLATION|CONVERSION|TABLE|SEQUENCE|SEQUENCE OWNED BY|DEFAULT|VIEW|MATERIALIZED VIEW|SHELL TYPE|TEXT SEARCH CONFIGURATION|TEXT SEARCH DICTIONARY|TEXT SEARCH PARSER|TEXT SEARCH TEMPLATE|PUBLICATION|PUBLICATION TABLE|PUBLICATION TABLES IN SCHEMA)$' { break }
            default { throw ('Unsupported schema object type: '+$type) }
        }
        $sql=$prelude+$text.Substring($h.Index,$end-$h.Index)
        if($type -eq 'SCHEMA') { $sql=[regex]::Replace($sql,'(?m)^CREATE SCHEMA (?!IF NOT EXISTS )','CREATE SCHEMA IF NOT EXISTS ') }
        $result.Add([pscustomobject]@{ Phase=$phase; Type=$type; Key=($type+'|'+$h.Groups['schema'].Value+'|'+$h.Groups['name'].Value); Sql=$sql })
    }
    return $result.ToArray()
}

function New-StrokedRestoreSql {
    param([string]$Payload, $Manifest, [string]$OutputFolder)
    $blocks = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($name in @('managed-schema-reference.sql','schema.sql','migration-history-schema.sql')) {
        foreach ($block in @(Get-StrokedDumpBlocks (Join-Path $Payload $name))) {
            if ($seen.ContainsKey($block.Key)) {
                if ($seen[$block.Key] -cne $block.Sql) { throw 'Overlapping schema definitions differ between backup components.' }
                continue
            }
            $seen[$block.Key]=$block.Sql; $blocks.Add($block)
        }
    }
    $utf8=New-Object Text.UTF8Encoding($false)
    $bootstrap=@'
DO $roles$
DECLARE r text;
BEGIN
 FOREACH r IN ARRAY ARRAY['postgres','anon','authenticated','service_role','authenticator','supabase_auth_admin','supabase_storage_admin','supabase_realtime_admin','supabase_functions_admin','supabase_replication_admin','supabase_read_only_user','pgbouncer','dashboard_user','supabase_etl_admin'] LOOP
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('CREATE ROLE %I NOLOGIN',r); END IF;
 END LOOP;
END $roles$;
ALTER ROLE postgres SUPERUSER;
ALTER ROLE service_role BYPASSRLS;
'@
    [IO.File]::WriteAllText((Join-Path $OutputFolder 'bootstrap.sql'),$bootstrap,$utf8)
    $restore=New-Object Text.StringBuilder
    $null=$restore.AppendLine('\set ON_ERROR_STOP on')
    $null=$restore.AppendLine('BEGIN;')
    $null=$restore.AppendLine('SET check_function_bodies=false;')
    $null=$restore.AppendLine('\i /restore/bootstrap.sql')
    $null=$restore.AppendLine('\i /restore/roles.sql')
    foreach ($phase in 0..2) {
        foreach ($block in @($blocks.ToArray() | Where-Object {$_.Phase -eq $phase})) { $null=$restore.AppendLine($block.Sql) }
    }
    $null=$restore.AppendLine('SET session_replication_role=replica;')
    $null=$restore.AppendLine('\i /restore/data.sql')
    if (Test-Path -LiteralPath (Join-Path $Payload 'vault-data.sql')) { $null=$restore.AppendLine('\i /restore/vault-data.sql') }
    if (-not $Manifest.migrationHistoryAlreadyInPrimaryData) { $null=$restore.AppendLine('\i /restore/migration-history-data.sql') }
    $null=$restore.AppendLine('SET session_replication_role=origin;')
    foreach ($phase in 3..6) {
        foreach ($block in @($blocks.ToArray() | Where-Object {$_.Phase -eq $phase})) { $null=$restore.AppendLine($block.Sql) }
    }
    $null=$restore.AppendLine('COMMIT;')
    [IO.File]::WriteAllText((Join-Path $OutputFolder 'restore.sql'),$restore.ToString(),$utf8)
    $counts=New-Object Text.StringBuilder
    $null=$counts.AppendLine('DO $counts$ BEGIN')
    $expected=@{}
    foreach($p in $Manifest.copyTableRowCounts.PSObject.Properties) { $expected[$p.Name]=[long]$p.Value }
    if (-not $Manifest.migrationHistoryAlreadyInPrimaryData) {
        $history=Get-StrokedCopyInventory @((Join-Path $Payload 'migration-history-data.sql'))
        foreach ($name in $history.Keys) { $expected[$name]=[long]$history[$name] }
    }
    if ($expected.Count -lt 14) { throw 'The backup does not contain a complete table-count inventory.' }
    foreach ($name in @($expected.Keys | Sort-Object)) {
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_$]*\.[A-Za-z_][A-Za-z0-9_$]*$') { throw 'A table-count identifier is unsupported.' }
        $parts=$name.Split('.'); $qualified='"'+$parts[0]+'"."'+$parts[1]+'"'
        $null=$counts.AppendLine(('IF (SELECT count(*) FROM {0}) <> {1} THEN RAISE EXCEPTION ''Restored row count differs: {2}''; END IF;' -f $qualified,$expected[$name],$name))
    }
    $null=$counts.AppendLine('END $counts$;')
    [IO.File]::WriteAllText((Join-Path $OutputFolder 'counts.sql'),$counts.ToString(),$utf8)
    return $expected.Count
}

function Invoke-StrokedPostgresRestoreCheck {
    param([string]$RestoreBackupFolder='')
    $ErrorActionPreference='Stop'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root=Join-Path $env:LOCALAPPDATA 'StrokedBackup'
    if (-not $RestoreBackupFolder) { $RestoreBackupFolder=Join-Path $env:USERPROFILE 'OneDrive\Stroked back up' }
    $stage=Join-Path $root ('postgres-check-'+[Guid]::NewGuid().ToString('N'))
    $container='stroked-restore-'+[Guid]::NewGuid().ToString('N')
    $image='public.ecr.aws/supabase/postgres:17.12.0.000'
    $lock=$null; $created=$false; $passed=$false
    try {
        $lock=[IO.File]::Open((Join-Path $root 'database-backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        New-StrokedPrivateDirectory $stage
        $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $age=(Get-Command age.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $keygen=(Get-Command age-keygen.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $identity=Join-Path $root 'recovery-key.txt'
        Assert-StrokedNonemptyFile $identity
        Write-Host '1/4 Checking and decrypting the saved database archive privately...'
        $recipient=(Invoke-StrokedRecoveryNative $keygen @('-y',$identity) 'Recovery identity check').Text.Trim()
        if ($recipient -notmatch '^age1[0-9a-z]{20,100}$') { throw 'The local recovery recipient is not valid.' }
        $db=@(Get-ChildItem -LiteralPath $RestoreBackupFolder -File -Filter 'Stroked-database-*.zip.age' | Sort-Object LastWriteTimeUtc -Descending)
        if ($db.Count -lt 1) { throw 'The saved database archive was not found.' }
        $cipherHash=(Get-FileHash -LiteralPath $db[0].FullName).Hash
        $zip=Join-Path $stage 'database.zip'
        $null=Invoke-StrokedRecoveryNative $age @('--decrypt','-i',$identity,'-o',$zip,$db[0].FullName) 'Database archive decryption'
        $checked=Test-StrokedArchiveManifest $zip 'database' $recipient
        $manifest=$checked.Manifest
        $archive=[IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $entries=Get-StrokedZipFileEntries $archive
            foreach($name in @('roles.sql','schema.sql','data.sql','vault-data.sql','managed-schema-reference.sql','migration-history-schema.sql','migration-history-data.sql','vault-root-key.txt')) {
                if ($entries.ContainsKey($name)) { Copy-StrokedZipEntry $entries[$name] (Join-Path $stage $name) }
            }
        } finally { $archive.Dispose() }
        if ([IO.File]::ReadAllText((Join-Path $stage 'vault-root-key.txt')).Trim() -notmatch '^[0-9a-fA-F]{64}$') { throw 'The archived Vault root key has an invalid format.' }
        $tableCount=New-StrokedRestoreSql $stage $manifest $stage
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-isolated-postgres.sh') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify-restored-database.sql') -Destination $stage
        $null=Invoke-StrokedRecoveryNative $docker @('info','--format','{{.OSType}}') 'Docker engine check'
        $null=Invoke-StrokedRecoveryNative $docker @('image','inspect',$image) 'Cached PostgreSQL 17 image check'
        Write-Host '2/4 Starting an empty PostgreSQL 17 container with networking disabled...'
        $mount='type=bind,source='+$stage+',target=/restore,readonly'
        if ($stage.Contains(',')) { throw 'A comma in the private directory path is unsupported by the Docker mount.' }
        $null=Invoke-StrokedRecoveryNative $docker @('run','--detach','--pull','never','--name',$container,'--label','stroked.backup-restore=temporary','--network','none','--log-driver','none','--memory','1g','--shm-size','128m','--pids-limit','256','--user','postgres','--mount',$mount,'--entrypoint','/bin/sh',$image,'/restore/start-isolated-postgres.sh') 'Isolated PostgreSQL startup'
        $created=$true
        $ready=$false
        for($i=0;$i -lt 45;$i++) {
            try { $null=Invoke-StrokedRecoveryNative $docker @('exec',$container,'pg_isready','-h','/tmp','-U','supabase_admin','-d','postgres') 'PostgreSQL readiness'; $ready=$true; break }
            catch { if($i -eq 15 -or $i -eq 30){Write-Host 'Still starting the temporary database...'}; Start-Sleep -Seconds 1 }
        }
        if(-not $ready) { throw 'The temporary PostgreSQL server did not become ready. No live connection was attempted.' }
        $version=(Invoke-StrokedRecoveryNative $docker @('exec',$container,'psql','-X','-h','/tmp','-U','supabase_admin','-d','postgres','-Atc','SHOW server_version_num') 'PostgreSQL version check').Text.Trim()
        if ($version -notmatch '^17[0-9]{4}$') { throw 'The restore container is not running PostgreSQL 17.' }
        Write-Host '3/4 Restoring roles, managed/application schemas and every exported data table...'
        $base=@('exec',$container,'psql','-X','-q','-h','/tmp','-U','supabase_admin','-d','postgres','--set','ON_ERROR_STOP=1','--set','VERBOSITY=terse')
        $null=Invoke-StrokedRecoveryNative $docker ($base+@('-f','/restore/restore.sql')) 'Offline SQL restore'
        Write-Host '4/4 Comparing every table count and checking Vault and administrator protection...'
        $null=Invoke-StrokedRecoveryNative $docker ($base+@('-f','/restore/counts.sql')) 'Restored table counts'
        $null=Invoke-StrokedRecoveryNative $docker ($base+@('-f','/restore/verify-restored-database.sql')) 'Restored security and Vault checks'
        $null=Invoke-StrokedRecoveryNative $docker @('rm','--force','--volumes',$container) 'Temporary database cleanup'
        $created=$false
        $report=[ordered]@{ formatVersion=1; checkedUtc=[DateTime]::UtcNow.ToString('o'); databaseArchive=$db[0].Name; sha256=$cipherHash; postgresImage=$image; countedTables=$tableCount; postgresLogicalRestorePassed=$true; vaultDecryptCheckPassed=$true; administratorDatabaseChecksPassed=$true; liveDatabaseContacted=$false; network='none'; fullSiteRestorePassed=$false }
        [IO.File]::WriteAllText((Join-Path $root 'postgres-restore-check-report.json'),($report|ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        $passed=$true
        Write-Host ''
        Write-Host 'DATABASE RESTORE CHECK PASSED' -ForegroundColor Green
        Write-Host ('Restored and compared '+$tableCount+' table counts; Vault decryption and administrator database checks passed.')
        Write-Host 'The temporary database was removed. The live website was untouched.'
        Write-Host 'Browser login, email/payments and external provider settings are separate checks.'
    }
    finally {
        if($created) { try {$null=Invoke-StrokedRecoveryNative $docker @('rm','--force','--volumes',$container) 'Temporary database cleanup'} catch {Write-Host ('Temporary container cleanup needs attention: '+$container)} }
        if(Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if($null -ne $lock) {$lock.Dispose()}
        if(-not $passed) {Write-Host 'The restore drill is not marked passed. Existing encrypted backups are retained.'}
    }
}

if(-not $RestoreHelperFolder) {$RestoreHelperFolder=$PSScriptRoot}
. (Join-Path $RestoreHelperFolder 'Stroked-Database-Backup.ps1')
. (Join-Path $RestoreHelperFolder 'Stroked-Recovery-Check.ps1')
if($MyInvocation.InvocationName -ne '.') {
    try {Invoke-StrokedPostgresRestoreCheck -RestoreBackupFolder $RestoreBackupFolder}
    catch {Write-Host ('RESTORE CHECK STOPPED: '+$_.Exception.Message) -ForegroundColor Red; exit 1}
}
