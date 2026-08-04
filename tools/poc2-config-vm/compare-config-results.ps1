#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $PSScriptRoot 'common.ps1'
$evidenceRoot = Join-Path $kitRoot 'evidence'
$statePath = Join-Path $evidenceRoot 'state-before.json'
$originalPath = Join-Path $evidenceRoot 'original-result.json'
$modernPath = Join-Path $evidenceRoot 'modern-result.json'
$reportPath = Join-Path $evidenceRoot 'comparison-report.json'
. $commonScript

foreach ($path in @($statePath, $originalPath, $modernPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Required evidence was not found: {0}' -f $path)
    }
}
if (@(Get-Process -Name 'LhaForge' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close every LhaForge process before comparison.'
}

$before = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$original = Get-Content -LiteralPath $originalPath -Raw | ConvertFrom-Json
$modern = Get-Content -LiteralPath $modernPath -Raw | ConvertFrom-Json
$currentExternal = Get-ExternalState

$originalIniJson = Convert-ToCanonicalJson -Value $original.ini.entries
$modernIniJson = Convert-ToCanonicalJson -Value $modern.ini.entries
$semanticMatch = ($originalIniJson -ceq $modernIniJson)
$caldixMatch = ($original.caldixSha256 -ceq $modern.caldixSha256)
$externalMatch = ((Convert-ToCanonicalJson -Value $before.externalState) -ceq (Convert-ToCanonicalJson -Value $currentExternal))
$expectedPassed = ([bool]$original.passed -and [bool]$modern.passed)

$differences = @()
if (-not $semanticMatch) {
    $originalLines = @($original.ini.entries | ForEach-Object { '[{0}] {1}={2}' -f $_.section, $_.key, $_.value })
    $modernLines = @($modern.ini.entries | ForEach-Object { '[{0}] {1}={2}' -f $_.section, $_.key, $_.value })
    $differences = @(Compare-Object -ReferenceObject $originalLines -DifferenceObject $modernLines)
}

$passed = ($semanticMatch -and $caldixMatch -and $externalMatch -and $expectedPassed)
$classification = if ($passed) { 'MATCH' } else { 'UNKNOWN' }

$report = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    classification = $classification
    passed = $passed
    checks = [ordered]@{
        expectedValuesPassed = $expectedPassed
        semanticIniMatch = $semanticMatch
        caldixIniMatch = $caldixMatch
        externalAppDataProgramDataAndRegistryUnchanged = $externalMatch
    }
    differences = $differences
    originalBinary = $original.binary
    modernBinary = $modern.binary
    currentExternalState = $currentExternal
}
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
if ($expectedPassed) { Write-Host '[OK] Expected saved values passed for Original and Modern.' } else { Write-Host '[NG] Expected saved values did not pass.' }
if ($semanticMatch) { Write-Host '[OK] Original and Modern semantic INI contents match.' } else { Write-Host '[NG] Original and Modern semantic INI contents differ.' }
if ($caldixMatch) { Write-Host '[OK] Original and Modern LFCaldix.ini hashes match.' } else { Write-Host '[NG] Original and Modern LFCaldix.ini hashes differ.' }
if ($externalMatch) { Write-Host '[OK] External AppData, ProgramData, and registry state remained unchanged.' } else { Write-Host '[NG] External AppData, ProgramData, or registry state changed.' }
Write-Host ('[POC2-CONFIG] Report: {0}' -f $reportPath)
Write-Host ('[POC2-CONFIG] Classification: {0}' -f $classification)

if (-not $passed) {
    if ($differences.Count -gt 0) {
        Write-Host '[POC2-CONFIG] Semantic INI differences:'
        foreach ($difference in $differences) {
            Write-Host ('  {0} {1}' -f $difference.SideIndicator, $difference.InputObject)
        }
    }
    exit 1
}

Write-Host '[POC2-CONFIG] PoC 2-A config save/reload regression passed.'
exit 0
