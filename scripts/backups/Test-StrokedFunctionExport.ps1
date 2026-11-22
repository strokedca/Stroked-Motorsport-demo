#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'Stroked-Files-Backup.ps1'
$source = [IO.File]::ReadAllText($path)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'The files helper did not parse.' }
# Run the actual export statements with a synthetic CLI boundary. No hosted
# service, Docker daemon, owner configuration or credentials are accessed.
$start = $ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$functionWork'}, $true)
$end = $ast.Find({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Copy-Item' -and $node.Extent.Text -match '\$functionFolder'}, $true)
if ($null -eq $start -or $null -eq $end -or $end.Extent.EndOffset -le $start.Extent.StartOffset) { throw 'The isolated function-export stage was not found.' }
$export = [scriptblock]::Create($source.Substring($start.Extent.StartOffset, $end.Extent.EndOffset - $start.Extent.StartOffset))
$temp = Join-Path ([IO.Path]::GetTempPath()) ('stroked-function-export-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
$project = 'aodywiwkhtxwlscpqnda'; $SupabaseCliPath = 'synthetic-cli'
$script:mode = 'success'; $script:calls = @()
function Invoke-StrokedNative {
    param([string]$Program, [string[]]$Arguments, [string]$Step)
    if ($Program -cne 'synthetic-cli') { throw 'An unexpected executable was requested.' }
    $index = [Array]::IndexOf($Arguments, '--workdir')
    if ($index -lt 0 -or $index + 1 -ge $Arguments.Count) { throw 'Explicit workdir is required.' }
    $work = $Arguments[$index + 1]
    if ($work -ceq $configWork) { throw 'Function export reused the pulled-config workspace.' }
    $script:calls += $Step
    if ($Arguments[0] -ceq 'init') {
        $null = New-Item -ItemType Directory -Path (Join-Path $work 'supabase')
        [IO.File]::WriteAllText((Join-Path $work 'supabase/config.toml'), 'synthetic clean configuration')
    } elseif ($Arguments[0] -ceq 'functions' -and $Arguments[1] -ceq 'download') {
        if ($Arguments -cnotcontains '--use-api' -or $Arguments -cnotcontains ('--remote=' + $project)) { throw 'API export must pin the Stroked project.' }
        if ([IO.File]::ReadAllText((Join-Path $work 'supabase/config.toml')) -cne 'synthetic clean configuration') { throw 'The download configuration was not clean.' }
        if ($script:mode -ceq 'failed') { throw 'Synthetic download failure.' }
        foreach ($name in @('stroked-email-alerts', 'stroked-stripe-webhook')) {
            $folder = Join-Path $work ('supabase/functions/' + $name)
            $null = New-Item -ItemType Directory -Path $folder -Force
            if ($script:mode -cne 'empty') { [IO.File]::WriteAllText((Join-Path $folder 'index.ts'), ('synthetic code: ' + $name)) }
        }
    } else { throw 'An unexpected CLI operation was requested.' }
    return [pscustomobject]@{ Text='private synthetic output' }
}
try {
    foreach ($case in @('success', 'empty', 'failed')) {
        $script:mode = $case; $script:calls = @()
        $stage = Join-Path $temp $case
        $configWork = Join-Path $stage 'config-workspace'
        $configFolder = Join-Path $stage 'payload/supabase-reference'
        $null = New-Item -ItemType Directory -Path (Join-Path $configWork 'supabase') -Force
        $null = New-Item -ItemType Directory -Path $configFolder -Force
        $reference = Join-Path $configWork 'supabase/config.toml'
        [IO.File]::WriteAllText($reference, 'synthetic pulled hosted configuration')
        $threw = $false
        try { $null = & $export } catch { $threw = $true }
        if ($case -ceq 'success') {
            if ($threw) { throw 'The clean-workspace export failed.' }
            foreach ($name in @('stroked-email-alerts', 'stroked-stripe-webhook')) {
                $file = Join-Path $configFolder ('functions/' + $name + '/index.ts')
                if ([IO.File]::ReadAllText($file) -cne ('synthetic code: ' + $name)) { throw 'Exported code was not preserved.' }
            }
        } else {
            if (-not $threw) { throw 'An empty or failed function export was accepted.' }
            if (Test-Path (Join-Path $configFolder 'functions')) { throw 'A failed export was copied into the payload.' }
        }
        if ([IO.File]::ReadAllText($reference) -cne 'synthetic pulled hosted configuration') { throw 'The hosted configuration reference changed.' }
        if ($script:calls.Count -ne 2 -or $script:calls[0] -cne 'Function export workspace setup' -or $script:calls[1] -cne 'Deployed function source export') { throw 'The expected initialization/download order changed.' }
    }
    Write-Host 'Function-export tests passed: clean workspace, explicit project/API, preserved hosted reference and code, empty/failed export refusal.'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
