#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Stroked-Database-Backup.ps1'
$tokens = $null
$parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors.Message -join "`n") }
. $scriptPath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { $null = & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('stroked-backup-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
try {
    $dump = Join-Path $temp 'data.sql'
    $fixture = @'
COPY "auth"."users" (id, email) FROM stdin;
fake-user\tfake@example.invalid
COPY public.spoofed (id) FROM stdin;
\.
COPY public.events (id) FROM stdin;
\.
-- PostgreSQL database dump complete
'@
    [IO.File]::WriteAllText($dump, $fixture)
    $inventory = Get-StrokedCopyInventory @($dump)
    Assert-True ($inventory['auth.users'] -eq 2) 'COPY row counting failed.'
    Assert-True ($inventory['public.events'] -eq 0) 'Empty COPY table was lost.'
    Assert-True (-not $inventory.ContainsKey('public.spoofed')) 'Data content was mistaken for a COPY header.'
    [IO.File]::WriteAllText($dump, "COPY public.events (id) FROM stdin;`nvalue")
    Assert-Throws { Get-StrokedCopyInventory @($dump) } 'Truncated COPY export was accepted.'
    [IO.File]::WriteAllText($dump, "COPY public.events (id) FROM stdin;`n\.`n")
    Assert-Throws { Get-StrokedCopyInventory @($dump) } 'Missing dump footer was accepted.'
    [IO.File]::WriteAllText($dump, $fixture + "`nCOPY public.events (id) FROM stdin;`n\.`n")
    Assert-Throws { Get-StrokedCopyInventory @($dump) } 'Duplicate COPY table was accepted.'

    $fakeKey = ('ab' * 32)
    Assert-True ((Get-StrokedRootKey ("Target: test-project`n" + $fakeKey)) -eq $fakeKey) 'Plain root key parsing failed.'
    Assert-True ((Get-StrokedRootKey ('{"root_key":"' + $fakeKey + '"}')) -eq $fakeKey) 'JSON root key parsing failed.'
    Assert-Throws { Get-StrokedRootKey 'No key here' } 'Missing root key was accepted.'
    Assert-Throws { Get-StrokedRootKey ($fakeKey + "`n" + ('cd' * 32)) } 'Ambiguous root keys were accepted.'
    Assert-Throws { Get-StrokedRootKey ('x' + $fakeKey + 'x') } 'A key substring was accepted.'

    $private = Join-Path $temp 'private'
    New-StrokedPrivateDirectory $private
    Assert-True (Get-Acl -LiteralPath $private).AreAccessRulesProtected 'Private staging inherited broad ACLs.'
    $cipher = Join-Path $private 'fixture.zip.age'
    [IO.File]::WriteAllBytes($cipher, [byte[]](1, 2, 3, 4, 5))
    $dest = Join-Path $temp 'destination'
    $null = New-Item -ItemType Directory -Path $dest
    $hash = (Get-FileHash -LiteralPath $cipher -Algorithm SHA256).Hash
    $published = Publish-StrokedCiphertext $cipher $dest 'test.zip.age' $hash
    Assert-True ((Get-FileHash -LiteralPath $published).Hash -eq $hash) 'Published ciphertext hash differs.'
    Assert-Throws { Publish-StrokedCiphertext $cipher $dest 'test.zip.age' $hash } 'An existing archive was overwritten.'
    Assert-True ((Get-FileHash -LiteralPath $published).Hash -eq $hash) 'Failed second publication damaged the first archive.'
    Assert-Throws { Publish-StrokedCiphertext $cipher $dest 'bad.zip.age' ('0' * 64) } 'Changed ciphertext was accepted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $dest 'bad.zip.age'))) 'Unverified ciphertext was published.'
    Assert-Throws { Publish-StrokedCiphertext $cipher $dest '..\escape.zip.age' $hash } 'Archive path traversal was accepted.'

    $native = (Get-Command powershell.exe -CommandType Application).Source
    $result = Invoke-StrokedNative $native @('-NoProfile', '-Command', "[Console]::Error.WriteLine('synthetic-stderr'); Write-Output 'synthetic-stdout'; exit 0") 'Synthetic native capture'
    Assert-True ($result.Text.Contains('synthetic-stderr') -and $result.Text.Contains('synthetic-stdout')) 'Native output capture failed.'
    $failureMessage = ''
    try {
        $null = Invoke-StrokedNative $native @('-NoProfile', '-Command', "[Console]::Error.WriteLine('do-not-expose-canary'); exit 7") 'Synthetic native failure'
    }
    catch { $failureMessage = $_.Exception.Message }
    Assert-True ($failureMessage.Contains('exit 7')) 'Nonzero native exit was ignored.'
    Assert-True (-not $failureMessage.Contains('do-not-expose-canary')) 'Captured native output leaked into an error.'
    Write-Host 'Windows PowerShell backup helper checks passed (synthetic fixtures only).'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
# The deliberate native exit-7 probe must not become the CI shell's exit code.
exit 0
