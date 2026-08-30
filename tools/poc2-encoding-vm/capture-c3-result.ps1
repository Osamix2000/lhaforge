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
. (Join-Path $PSScriptRoot 'c3-common.ps1')

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence-c3'
$beforePath = Join-Path $evidenceRoot 'state-before-c3.json'
$targetRoot = Get-TargetRoot -Target $Target
$runRoot = Get-C3RunRecordRoot -Target $Target

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
    throw 'Run initialize-c3-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
    throw ('No C3 run records exist for target: {0}' -f $Target)
}

$required = @()
foreach ($case in Get-Poc2C3FrozenCases) {
    foreach ($op in @('list', 'test', 'extract')) {
        $required += ($op + '-' + $case.id + '.json')
    }
}
foreach ($name in $required) {
    $path = Join-Path $runRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Required C3 run record is missing: {0}' -f $path)
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

$output = Join-Path $evidenceRoot ($Target + '-c3-result.json')
Write-JsonUtf8NoBom -Value $result -Path $output -Depth 28

Write-Host ('[POC2-C3] Capture complete: {0}' -f $output)
Write-Host ('[POC2-C3] Run records: {0}' -f $runs.Count)
