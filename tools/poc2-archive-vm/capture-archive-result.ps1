#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('original', 'modern')]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-KitRoot
$targetRoot = Get-TargetRoot -Target $Target
$resultsRoot = Join-Path $targetRoot 'results'
$evidenceRoot = Join-Path $kitRoot 'evidence'
$beforePath = Join-Path $evidenceRoot 'state-before.json'

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
    throw 'Run initialize-archive-regression.ps1 first.'
}

$archivePath = Join-Path $resultsRoot 'compressed\roundtrip.zip'
$extractPath = Join-Path $resultsRoot 'extract'
$roundtripPath = Join-Path $resultsRoot 'roundtrip'
$manualPath = Get-ManualObservationPath -Target $Target

$manual = $null
if (Test-Path -LiteralPath $manualPath -PathType Leaf) {
    $manual = Get-Content -LiteralPath $manualPath -Raw | ConvertFrom-Json
}

$result = [ordered]@{
    target = $Target
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    exe = Get-FileEvidence -Path (Join-Path $targetRoot 'LhaForge.exe')
    dll = Get-FileEvidence -Path (Join-Path $targetRoot '7-ZIP32.DLL')
    extracted = Get-DirectoryInventory -Path $extractPath
    compressedZip = if (Test-Path -LiteralPath $archivePath -PathType Leaf) { Get-FileHashEvidence -Path $archivePath } else { $null }
    compressedZipEntries = Get-ZipInventory -Path $archivePath
    roundtrip = Get-DirectoryInventory -Path $roundtripPath
    manual = $manual
    external = Get-ExternalState
    tempZip = @(Get-TempZipState)
}

$output = Join-Path $evidenceRoot ($Target + '-result.json')
$result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $output -Encoding UTF8

Write-Host ('[POC2-ARCHIVE] Capture complete: {0}' -f $output)
Write-Host ('[POC2-ARCHIVE] Extracted files : {0}' -f $result.extracted.files.Count)
Write-Host ('[POC2-ARCHIVE] ZIP entries      : {0}' -f $result.compressedZipEntries.entries.Count)
Write-Host ('[POC2-ARCHIVE] Roundtrip files  : {0}' -f $result.roundtrip.files.Count)
if ($null -eq $manual) {
    Write-Warning 'Manual List/Test observations are missing.'
}
