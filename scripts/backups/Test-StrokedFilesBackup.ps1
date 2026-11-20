#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$paths = @('Stroked-Database-Backup.ps1', 'Stroked-Files-Backup.ps1')
foreach ($name in $paths) {
    $tokens = $null; $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ($parseErrors.Message -join "`n") }
}
. (Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1')
. (Join-Path $PSScriptRoot 'Stroked-Files-Backup.ps1')
function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { $null = & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('stroked-files-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
try {
    $json = '{"formatVersion":1,"projectRef":"aodywiwkhtxwlscpqnda","buckets":[],"objects":[]}'
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $framed = 'STROKED_INVENTORY_V1:' + $base64 + ':END_STROKED_INVENTORY_V1'
    $inventory = ConvertFrom-StrokedInventoryOutput ('Target: test' + "`n" + '[{"backup_inventory":"' + $framed + '"}]')
    Assert-True (@($inventory.objects).Count -eq 0) 'Empty Storage inventory was not preserved.'
    Assert-Throws { ConvertFrom-StrokedInventoryOutput 'unframed' } 'Unframed inventory was accepted.'
    Assert-Throws { ConvertFrom-StrokedInventoryOutput ($framed + $framed) } 'Ambiguous inventory was accepted.'
    $bad = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json.Replace('aodywiwkhtxwlscpqnda', 'different-project')))
    Assert-Throws { ConvertFrom-StrokedInventoryOutput ('STROKED_INVENTORY_V1:' + $bad + ':END_STROKED_INVENTORY_V1') } 'Wrong project inventory was accepted.'
    Assert-True ((Get-StrokedStorageUrl 'bucket' 'folder/a #?%.png') -ceq 'ss:///bucket/folder/a%20%23%3F%25.png') 'Storage key URL encoding changed the key.'
    Assert-Throws { Get-StrokedStorageUrl 'bad/bucket' 'file.png' } 'An invalid bucket name was accepted.'
    $a = [pscustomobject]@{ buckets = @([pscustomobject]@{id='b'; public=$false}); objects = @() }
    $b = [pscustomobject]@{ buckets = @([pscustomobject]@{id='b'; public=$true}); objects = @() }
    Assert-StrokedStorageUnchanged $a $a
    Assert-Throws { Assert-StrokedStorageUnchanged $a $b } 'A changed bucket privacy setting was ignored.'

    $payload = Join-Path $temp 'payload'
    $nested = Join-Path $payload 'functions\example'
    $null = New-Item -ItemType Directory -Path $nested -Force
    $ordinary = Join-Path $nested 'index.ts'
    $hidden = Join-Path $payload '.hidden-config'
    [IO.File]::WriteAllText($ordinary, 'synthetic function code')
    [IO.File]::WriteAllText($hidden, 'synthetic hidden setting')
    [IO.File]::SetAttributes($hidden, [IO.FileAttributes]::Hidden)
    $zipPath = Join-Path $temp 'payload.zip'
    New-StrokedPayloadZip $payload $zipPath
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
        Assert-True ($entryNames -ccontains 'functions/example/index.ts') 'ZIP lost a nested function file.'
        Assert-True ($entryNames -ccontains '.hidden-config') 'ZIP lost a hidden configuration file.'
    }
    finally { $zip.Dispose() }

    # Check that a source-history bundle can actually populate a new repository.
    $git = (Get-Command git.exe -CommandType Application).Source
    $repo = Join-Path $temp 'repo'
    $null = Invoke-StrokedNative $git @('init', '--initial-branch=main', $repo) 'Synthetic source initialization'
    [IO.File]::WriteAllText((Join-Path $repo 'source.txt'), 'synthetic source snapshot')
    $null = Invoke-StrokedNative $git @('-C', $repo, 'add', 'source.txt') 'Synthetic source staging'
    $null = Invoke-StrokedNative $git @('-C', $repo, '-c', 'user.name=Backup test', '-c', 'user.email=backup@example.invalid', 'commit', '-m', 'Synthetic fixture') 'Synthetic source commit'
    $bundle = Join-Path $temp 'source.bundle'
    $null = Invoke-StrokedNative $git @('-C', $repo, 'bundle', 'create', $bundle, '--all') 'Synthetic source bundle'
    $restored = Join-Path $temp 'restored'
    $null = Invoke-StrokedNative $git @('clone', $bundle, $restored) 'Synthetic bundle restore'
    Assert-True ([IO.File]::ReadAllText((Join-Path $restored 'source.txt')) -ceq 'synthetic source snapshot') 'Git bundle did not restore the original source.'
    $starter = Join-Path $PSScriptRoot 'Setup-and-Run-Files-Backup.cmd'
    $starterText = [IO.File]::ReadAllText($starter)
    $testBundle = Join-Path $temp "Jason's files & test folder"
    $null = New-Item -ItemType Directory -Path $testBundle
    foreach ($name in $paths) {
        $source = Join-Path $PSScriptRoot $name
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        Assert-True ($starterText.ToLowerInvariant().Contains($hash.ToLowerInvariant())) 'Files starter checksum is stale.'
        Copy-Item -LiteralPath $source -Destination $testBundle
    }
    Copy-Item -LiteralPath $starter -Destination $testBundle
    $installed = Join-Path $temp 'installed files helpers'
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /s /c ""' + (Join-Path $testBundle 'Setup-and-Run-Files-Backup.cmd') + '" --install-only < NUL"'
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.EnvironmentVariables['STROKED_FILES_INSTALL_DIR'] = $installed
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $outputText = $process.StandardOutput.ReadToEnd()
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Assert-True ($process.ExitCode -eq 0) ('Files starter failed: ' + $outputText + $errorText)
        Assert-True ($outputText.Contains('Files helpers installed. No backup was started.')) 'Files installer unexpectedly ran the backup.'
    }
    finally { $process.Dispose() }
    foreach ($name in $paths) {
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $installed $name)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash) 'Files installer changed a helper.'
    }
    Write-Host 'Files backup checks passed (synthetic fixtures; no live service access).'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
exit 0
