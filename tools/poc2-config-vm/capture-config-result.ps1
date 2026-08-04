#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Original', 'Modern')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [switch]$ReloadVerified
)

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $PSScriptRoot 'common.ps1'
$evidenceRoot = Join-Path $kitRoot 'evidence'
$statePath = Join-Path $evidenceRoot 'state-before.json'
. $commonScript

if (-not $ReloadVerified) {
    throw 'Rerun only after reopening the target and manually verifying all five saved settings.'
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw 'Run initialize-config-regression.ps1 before capturing a result.'
}
if (@(Get-Process -Name 'LhaForge' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close every LhaForge process before capturing the result.'
}

$folderName = $Target.ToLowerInvariant()
$targetRoot = Join-Path $kitRoot $folderName
$iniPath = Join-Path $targetRoot 'LhaForge.ini'
$caldixPath = Join-Path $targetRoot 'LFCaldix.ini'
$exePath = Join-Path $targetRoot 'LhaForge.exe'

$ini = Read-IniSemantic -Path $iniPath
$expected = @(
    [pscustomobject]@{ section = 'LogView'; key = 'LogViewEvent'; value = '1' },
    [pscustomobject]@{ section = 'Output'; key = 'WarnNetwork'; value = '1' },
    [pscustomobject]@{ section = 'Output'; key = 'OnDirNotFound'; value = '1' },
    [pscustomobject]@{ section = 'Compress'; key = 'OpenFolder'; value = '0' },
    [pscustomobject]@{ section = 'FileListWindow'; key = 'ExitWithEscape'; value = '1' },
    [pscustomobject]@{ section = 'Update'; key = 'AskUpdate'; value = '0' }
)

$checks = @()
$allExpected = $true
foreach ($item in $expected) {
    $actual = Get-IniValue -Ini $ini -Section $item.section -Key $item.key
    $passed = ($actual -ceq $item.value)
    if (-not $passed) { $allExpected = $false }
    $checks += [pscustomobject]@{
        section = $item.section
        key = $item.key
        expected = $item.value
        actual = $actual
        passed = $passed
    }

    if ($passed) {
        Write-Host ('[OK] [{0}] {1}={2}' -f $item.section, $item.key, $actual)
    }
    else {
        Write-Host ('[NG] [{0}] {1}: expected {2}, actual {3}' -f $item.section, $item.key, $item.value, $actual)
    }
}

$encodingPassed = ($ini.encoding -eq 'utf-16le-bom')
if ($encodingPassed) {
    Write-Host ('[OK] INI encoding: {0}' -f $ini.encoding)
}
else {
    Write-Host ('[NG] INI encoding: {0}' -f $ini.encoding)
}

$result = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    target = $Target
    reloadVerified = $true
    binary = Get-FileEvidence -Path $exePath
    ini = $ini
    caldixSha256 = (Get-FileHash -LiteralPath $caldixPath -Algorithm SHA256).Hash.ToLowerInvariant()
    expectedChecks = $checks
    passed = ($allExpected -and $encodingPassed)
}
$resultPath = Join-Path $evidenceRoot ($folderName + '-result.json')
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Copy-Item -LiteralPath $iniPath -Destination (Join-Path $evidenceRoot ($folderName + '-LhaForge.ini')) -Force
Copy-Item -LiteralPath $caldixPath -Destination (Join-Path $evidenceRoot ($folderName + '-LFCaldix.ini')) -Force

Write-Host ''
Write-Host ('[POC2-CONFIG] Result: {0}' -f $resultPath)
if (-not $result.passed) {
    Write-Host '[POC2-CONFIG] Capture failed. Correct the manual test or restore the VM snapshot.'
    exit 1
}
Write-Host ('[POC2-CONFIG] {0} save/reload capture passed.' -f $Target)
