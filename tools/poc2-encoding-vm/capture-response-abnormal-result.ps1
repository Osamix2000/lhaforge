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
. (Join-Path $PSScriptRoot 'response-common.ps1')
. (Join-Path $PSScriptRoot 'abnormal-response-common.ps1')

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence-response-abnormal'
$beforePath = Join-Path $evidenceRoot 'state-before.json'
$runRoot = Get-Poc2C2AbnormalRunRecordRoot -Target $Target
$targetRoot = Get-TargetRoot -Target $Target

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
	throw 'Run initialize-response-abnormal-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
	throw ('No abnormal C2 run records exist for target: {0}' -f $Target)
}

$before = Read-JsonUtf8 -Path $beforePath
$captureRuntime = Assert-Poc2C2AbnormalRuntime -ExpectedRuntime $before.runtime -KitRoot $kitRoot

$required = @()
foreach ($case in Get-Poc2C2AbnormalCases) {
	$required += ('response-abnormal-' + $case.id + '.json')
}

foreach ($name in $required) {
	$path = Join-Path $runRoot $name
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		throw ('Required abnormal C2 run record is missing: {0}' -f $path)
	}
}

$runs = @()
foreach ($file in Get-ChildItem -LiteralPath $runRoot -Filter '*.json' -File | Sort-Object Name) {
	$runs += (Read-JsonUtf8 -Path $file.FullName)
}

if ($runs.Count -ne $required.Count) {
	throw ('Unexpected abnormal C2 run record count for {0}. Expected {1}, actual {2}.' -f $Target, $required.Count, $runs.Count)
}

$result = [ordered]@{
	schemaVersion = 1
	target = $Target
	capturedUtc = [DateTime]::UtcNow.ToString('o')
	exe = Get-FileEvidence -Path (Join-Path $targetRoot 'LhaForge.exe')
	dll = Get-FileEvidence -Path (Join-Path $targetRoot '7-ZIP32.DLL')
	runtime = $captureRuntime
	runs = @($runs)
	external = Get-ExternalState
	tempZip = @(Get-TempZipState)
}

$output = Join-Path $evidenceRoot ($Target + '-result.json')
Write-JsonUtf8NoBom -Value $result -Path $output -Depth 30

Write-Host ('[POC2-RSP-ABN] Capture complete: {0}' -f $output)
Write-Host ('[POC2-RSP-ABN] Run records: {0}' -f $runs.Count)
