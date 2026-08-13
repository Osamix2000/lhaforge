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
$evidenceRoot = Join-Path $kitRoot 'evidence'
$beforePath = Join-Path $evidenceRoot 'state-before.json'
$runRoot = Get-RunRecordRoot -Target $Target
$targetRoot = Get-TargetRoot -Target $Target

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
    throw 'Run initialize-encoding-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
    throw ('No run records exist for target: {0}' -f $Target)
}

$required = @(
    'list.json',
    'test.json',
    'pathprobe-ascii.json',
    'pathprobe-japanese.json',
    'pathprobe-emoji.json',
    'pathprobe-supplementary.json',
    'pathprobe-combining.json',
    'pathprobe-nfc.json',
    'pathprobe-nfd.json',
    'compress.json',
    'reextract.json'
)

foreach ($name in $required) {
    $path = Join-Path $runRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Required run record is missing: {0}' -f $path)
    }
}

$runs = @()
foreach ($file in Get-ChildItem -LiteralPath $runRoot -Filter '*.json' -File | Sort-Object Name) {
    $runs += (Read-JsonUtf8 -Path $file.FullName)
}

$result = [ordered]@{
    schemaVersion = 1
    target = $Target
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    exe = Get-FileEvidence -Path (Join-Path $targetRoot 'LhaForge.exe')
    dll = Get-FileEvidence -Path (Join-Path $targetRoot '7-ZIP32.DLL')
    runs = @($runs)
    external = Get-ExternalState
    tempZip = @(Get-TempZipState)
}

$output = Join-Path $evidenceRoot ($Target + '-result.json')
Write-JsonUtf8NoBom -Value $result -Path $output -Depth 22

Write-Host ('[POC2-ENC] Capture complete: {0}' -f $output)
Write-Host ('[POC2-ENC] Run records: {0}' -f $runs.Count)
