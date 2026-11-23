function Split-StrokedSchemaStatements {
    param([string]$Text)
    # CLI v3 removes header/footer comments by default. Parse statement boundaries
    # without relying on comments, and never split routine bodies or SQL literals.
    $parts=New-Object 'System.Collections.Generic.List[string]'
    $dollar=New-Object Text.RegularExpressions.Regex('\G\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$')
    $start=-1; $i=0
    while($i -lt $Text.Length) {
        $c=$Text[$i]
        if($c -eq '-' -and $i+1 -lt $Text.Length -and $Text[$i+1] -eq '-') {
            $end=$Text.IndexOf("`n",$i+2); if($end -lt 0){$i=$Text.Length}else{$i=$end+1}; continue
        }
        if($c -eq '/' -and $i+1 -lt $Text.Length -and $Text[$i+1] -eq '*') {
            $depth=1; $i+=2
            while($i -lt $Text.Length -and $depth -gt 0) {
                if($i+1 -lt $Text.Length -and $Text.Substring($i,2) -ceq '/*'){$depth++;$i+=2}
                elseif($i+1 -lt $Text.Length -and $Text.Substring($i,2) -ceq '*/'){$depth--;$i+=2}
                else{$i++}
            }
            if($depth -gt 0){throw 'A schema export ends inside a block comment.'};continue
        }
        if($start -lt 0) {
            if([char]::IsWhiteSpace($c)){$i++;continue}
            if($c -eq '\') {
                $end=$Text.IndexOf("`n",$i); if($end -lt 0){$end=$Text.Length}
                if($Text.Substring($i,$end-$i) -notmatch '^\\(?:un)?restrict\s+[A-Za-z0-9]+\s*$'){throw 'Unexpected psql command in a schema export.'}
                $i=$end;continue
            }
            $start=$i
        }
        if($c -eq "'" -or $c -eq '"') {
            $quote=$c; $escaped=$false
            if($quote -eq "'" -and $i -gt 0 -and $Text[$i-1] -match '[eE]' -and ($i -lt 2 -or $Text[$i-2] -notmatch '[A-Za-z0-9_$]')){$escaped=$true}
            $closed=$false; $i++
            while($i -lt $Text.Length) {
                if($escaped -and $Text[$i] -eq '\'){$i+=2;continue}
                if($Text[$i] -eq $quote) {
                    if($i+1 -lt $Text.Length -and $Text[$i+1] -eq $quote){$i+=2;continue}
                    $i++;$closed=$true;break
                }
                $i++
            }
            if(-not $closed){throw 'A schema export ends inside a quoted value.'};continue
        }
        if($c -eq '$') {
            $match=$dollar.Match($Text,$i)
            if($match.Success) {
                $end=$Text.IndexOf($match.Value,$i+$match.Length,[StringComparison]::Ordinal)
                if($end -lt 0){throw 'A schema export ends inside a routine body.'}
                $i=$end+$match.Length;continue
            }
        }
        if($c -eq ';') {
            $parts.Add($Text.Substring($start,$i-$start+1).Trim());$start=-1
        }
        $i++
    }
    if($start -ge 0){throw 'A schema export ends before its final SQL statement is complete.'}
    if($parts.Count -lt 1){throw 'A schema export contains no SQL statements.'}
    return $parts.ToArray()
}

function Get-StrokedDumpBlocks {
    param([string]$Path)
    $text=[IO.File]::ReadAllText($Path).Replace("`r`n","`n")
    $result=New-Object 'System.Collections.Generic.List[object]'
    foreach($statement in @(Split-StrokedSchemaStatements $text)) {
        $sql=$statement; $phase=2; $type='DEFINITION'
        $key='SQL|'+$sql
        # Classify only a statement's opening words. Quoted routine bodies are
        # retained byte-for-byte and do not affect the ordering of other objects.
        switch -Regex ($sql) {
            '^(?i:CREATE\s+SCHEMA)\s+(?:IF\s+NOT\s+EXISTS\s+)?(?<id>"(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_$]*)\s*;' {
                $phase=0;$type='SCHEMA';$key='SCHEMA|'+$Matches.id
                $sql=[regex]::Replace($sql,'^(?i:CREATE\s+SCHEMA)\s+(?!IF\s+NOT\s+EXISTS\s+)','CREATE SCHEMA IF NOT EXISTS ');break
            }
            '^(?i:CREATE\s+EXTENSION)\s+(?:IF\s+NOT\s+EXISTS\s+)?(?<id>"(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_$]*)(?=\s|;)' {
                $phase=1;$type='EXTENSION';$key='EXTENSION|'+$Matches.id;break
            }
            '^(?i:ALTER\s+SCHEMA|SET\s+(?!default_tablespace\b|default_table_access_method\b)|SELECT\s+(?:"?pg_catalog"?\.)?"?set_config"?\s*\()' {$phase=0;$type='PRELUDE';break}
            '^(?i:CREATE\s+(?:UNIQUE\s+)?INDEX|CREATE\s+STATISTICS|ALTER\s+INDEX)' {$phase=3;$type='INDEX';break}
            '^(?i:ALTER\s+TABLE)\b' {
                if($sql -match '(?i)\bFOREIGN\s+KEY\b|\bVALIDATE\s+CONSTRAINT\b'){$phase=4;$type='FK CONSTRAINT'}
                elseif($sql -match '(?i)\bADD\s+(?:CONSTRAINT|PRIMARY\s+KEY|UNIQUE|CHECK|EXCLUDE)\b|\bATTACH\s+PARTITION\b'){$phase=3;$type='CONSTRAINT'}
                elseif($sql -match '(?i)\b(?:ENABLE|DISABLE|FORCE|NO\s+FORCE)\s+(?:ROW\s+LEVEL\s+SECURITY|TRIGGER)\b'){$phase=5;$type='ROW SECURITY'}
                break
            }
            '^(?i:CREATE\s+(?:OR\s+REPLACE\s+)?(?:CONSTRAINT\s+)?(?:EVENT\s+)?TRIGGER|ALTER\s+(?:EVENT\s+)?TRIGGER|CREATE\s+POLICY|ALTER\s+POLICY|CREATE\s+(?:OR\s+REPLACE\s+)?RULE)' {$phase=5;$type='POLICY OR TRIGGER';break}
            '^(?i:GRANT|REVOKE|ALTER\s+DEFAULT\s+PRIVILEGES|COMMENT\s+ON|SECURITY\s+LABEL|RESET\s+ALL)\b' {$phase=6;$type='ACL OR COMMENT';break}
            '^(?i:CREATE\s+(?:OR\s+REPLACE\s+)?(?:UNLOGGED\s+)?(?:TYPE|DOMAIN|FUNCTION|PROCEDURE|AGGREGATE|OPERATOR|CAST|COLLATION|CONVERSION|TABLE|SEQUENCE|VIEW|MATERIALIZED\s+VIEW|TEXT\s+SEARCH|PUBLICATION)|ALTER\s+(?:TYPE|DOMAIN|FUNCTION|PROCEDURE|AGGREGATE|OPERATOR|COLLATION|CONVERSION|SEQUENCE|VIEW|MATERIALIZED\s+VIEW|TEXT\s+SEARCH|PUBLICATION)|SET\s+(?:default_tablespace|default_table_access_method))\b' {break}
            default {throw ('Unsupported SQL statement in '+[IO.Path]::GetFileName($Path)+'. No statement contents have been displayed.')}
        }
        $result.Add([pscustomobject]@{Phase=$phase;Type=$type;Key=$key;Sql=$sql})
    }
    return $result.ToArray()
}

