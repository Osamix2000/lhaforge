#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence'
$manifest = Get-Content -LiteralPath (Join-Path $kitRoot 'manifest.json') -Raw | ConvertFrom-Json
$before = Get-Content -LiteralPath (Join-Path $evidenceRoot 'state-before.json') -Raw | ConvertFrom-Json

$originalPath = Join-Path $evidenceRoot 'original-result.json'
$modernPath = Join-Path $evidenceRoot 'modern-result.json'
if (-not (Test-Path -LiteralPath $originalPath -PathType Leaf)) {
    throw 'Original result is missing. Run capture-archive-result.ps1 -Target original.'
}
if (-not (Test-Path -LiteralPath $modernPath -PathType Leaf)) {
    throw 'Modern result is missing. Run capture-archive-result.ps1 -Target modern.'
}

$original = Get-Content -LiteralPath $originalPath -Raw | ConvertFrom-Json
$modern = Get-Content -LiteralPath $modernPath -Raw | ConvertFrom-Json
$expected = Get-DirectoryInventory -Path (Join-Path $kitRoot 'fixture\input')
$expectedZipFingerprint = Get-ZipFileEntryFingerprintFromDirectoryInventory -Inventory $expected

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Check {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host ('[OK] ' + $Message)
    }
    else {
        Write-Host ('[NG] ' + $Message)
        $failures.Add($Message)
    }
}

Check ($original.dll.sha256 -ceq $modern.dll.sha256) 'Original and Modern use the same 7-ZIP32.DLL bytes.'
Check ($original.dll.sha256 -ceq [string]$manifest.sevenZipDllSource.sha256) 'Staged DLL matches the selected host DLL.'

Check ([string]$original.extracted.fingerprint -ceq [string]$expected.fingerprint) 'Original extraction matches the fixture by path, size, and SHA-256.'
Check ([string]$modern.extracted.fingerprint -ceq [string]$expected.fingerprint) 'Modern extraction matches the fixture by path, size, and SHA-256.'
Check ([string]$original.extracted.fingerprint -ceq [string]$modern.extracted.fingerprint) 'Original and Modern extraction results match.'

Check ([string]$original.roundtrip.fingerprint -ceq [string]$expected.fingerprint) 'Original compress -> re-extract matches the fixture.'
Check ([string]$modern.roundtrip.fingerprint -ceq [string]$expected.fingerprint) 'Modern compress -> re-extract matches the fixture.'
Check ([string]$original.roundtrip.fingerprint -ceq [string]$modern.roundtrip.fingerprint) 'Original and Modern roundtrip results match.'

Check ($original.compressedZipEntries.exists) 'Original compressed ZIP can be opened by .NET ZipArchive.'
Check ($modern.compressedZipEntries.exists) 'Modern compressed ZIP can be opened by .NET ZipArchive.'
if ($original.compressedZipEntries.exists) {
    Check ([string]$original.compressedZipEntries.fileFingerprint -ceq [string]$expectedZipFingerprint) 'Original compressed ZIP has the expected logical files and sizes.'
}
if ($modern.compressedZipEntries.exists) {
    Check ([string]$modern.compressedZipEntries.fileFingerprint -ceq [string]$expectedZipFingerprint) 'Modern compressed ZIP has the expected logical files and sizes.'
}
if ($original.compressedZipEntries.exists -and $modern.compressedZipEntries.exists) {
    Check ([string]$original.compressedZipEntries.fileFingerprint -ceq [string]$modern.compressedZipEntries.fileFingerprint) 'Original and Modern compressed ZIP semantic file lists match.'
}

Check ([string]$original.external.appData.fingerprint -ceq [string]$before.external.appData.fingerprint) 'Original did not change AppData LhaForge file content.'
Check ([string]$original.external.programData.fingerprint -ceq [string]$before.external.programData.fingerprint) 'Original did not change ProgramData LhaForge file content.'
Check ([string]$modern.external.appData.fingerprint -ceq [string]$before.external.appData.fingerprint) 'Modern did not change AppData LhaForge file content.'
Check ([string]$modern.external.programData.fingerprint -ceq [string]$before.external.programData.fingerprint) 'Modern did not change ProgramData LhaForge file content.'

$beforeTemp = @($before.tempZip | ForEach-Object { [string]$_.path })
$originalTempNew = @($original.tempZip | Where-Object { $beforeTemp -notcontains [string]$_.path })
$modernTempNew = @($modern.tempZip | Where-Object { $beforeTemp -notcontains [string]$_.path })
if ($originalTempNew.Count -eq 0) {
    Write-Host '[OK] Original left no new zip*.tmp residue.'
}
else {
    $warnings.Add('Original left new zip*.tmp files in TEMP.')
    Write-Warning 'Original left new zip*.tmp files in TEMP.'
}
if ($modernTempNew.Count -eq 0) {
    Write-Host '[OK] Modern left no new zip*.tmp residue.'
}
else {
    $warnings.Add('Modern left new zip*.tmp files in TEMP.')
    Write-Warning 'Modern left new zip*.tmp files in TEMP.'
}

$manualComplete = $true
foreach ($result in @($original, $modern)) {
    if ($null -eq $result.manual) {
        $manualComplete = $false
        Write-Warning ('Manual observations are missing for {0}.' -f $result.target)
        continue
    }
    Check ([bool]$result.manual.list) ('{0} List UI showed the expected archive contents.' -f $result.target)
    Check ([bool]$result.manual.test) ('{0} archive Test UI reported success.' -f $result.target)
}

if ($failures.Count -gt 0) {
    $classification = 'MISMATCH'
}
elseif (-not $manualComplete) {
    $classification = 'AUTOMATED_MATCH_MANUAL_PENDING'
}
else {
    $classification = 'MATCH'
}

$summary = [ordered]@{
    comparedUtc = [DateTime]::UtcNow.ToString('o')
    classification = $classification
    failures = @($failures)
    warnings = @($warnings)
    note = 'ZIP binary hashes are intentionally not used as the primary compression regression criterion.'
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'comparison.json') -Encoding UTF8

Write-Host ''
Write-Host ('[POC2-ARCHIVE] Classification: {0}' -f $classification)
if ($warnings.Count -gt 0) {
    Write-Host ('[POC2-ARCHIVE] Warnings: {0}' -f $warnings.Count)
}
if ($classification -eq 'MISMATCH') { exit 1 }
if ($classification -eq 'AUTOMATED_MATCH_MANUAL_PENDING') { exit 2 }
exit 0
