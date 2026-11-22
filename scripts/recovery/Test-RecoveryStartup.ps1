#Requires -Version 5.1
param([string]$Package=(Join-Path $PSScriptRoot 'local-website'))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Local-Core.ps1')
. (Join-Path $Package 'Proxy-Tools.ps1')
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function New-State {@{Project='StrokedRecoverySite';ContainerID=('a'*64);LocalTOTPRestartRequested=$true;ImportAttempted=$false;ImportCommitted=$false}}
function New-Metadata {[pscustomobject]@{postgres='17.12';authUsers=0;appTables=0;outboundExtensions=0;markerExists=$false}}
$db=[pscustomobject]@{Name='/supabase_db_StrokedRecoverySite';Id=('b'*64);Config=[pscustomobject]@{Labels=[pscustomobject]@{'com.supabase.cli.project'='StrokedRecoverySite'}}}
$s=New-State;Confirm-DrillRestartMetadata $s $db (New-Metadata)
Assert-True ($s.ContainerID -ceq ('b'*64) -and -not $s.LocalTOTPRestartRequested) 'Empty pre-import restart did not rebind checkpoint.'
foreach($kind in @('importAttempted','importCommitted','noIntent','users','tables','outbound','marker','missing','foreignDatabase')){
    $s=New-State;$m=New-Metadata;$candidate=$db
    switch($kind){
        importAttempted {$s.ImportAttempted=$true}
        importCommitted {$s.ImportCommitted=$true}
        noIntent {$s.LocalTOTPRestartRequested=$false}
        users {$m.authUsers=1}
        tables {$m.appTables=1}
        outbound {$m.outboundExtensions=1}
        marker {$m.markerExists=$true}
        missing {$m.PSObject.Properties.Remove('authUsers')}
        foreignDatabase {$candidate=[pscustomobject]@{Name='/supabase_db_OtherProject';Id=('c'*64)}}
    }
    $failed=$false;try{Confirm-DrillRestartMetadata $s $candidate $m}catch{$failed=$true}
    Assert-True $failed ('Restart guard accepted '+$kind)
    Assert-True ($s.ContainerID -ceq ('a'*64)) 'A failed restart guard changed the checkpoint.'
}
Write-Host ('PASS: PowerShell '+$PSVersionTable.PSVersion+'; checkpoint replacement only after explicit pre-import intent and complete empty-database proof; imported/nonempty/outbound/marker/missing/foreign cases refused.')
