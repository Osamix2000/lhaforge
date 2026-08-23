#Requires -Version 5.1
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidateSet('original', 'modern')]
	[string]$Target,

	[Parameter(Mandatory = $true)]
	[string]$CaseId,

	[ValidateRange(10, 600)]
	[int]$TimeoutSeconds = 120,

	[switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'response-common.ps1')
. (Join-Path $PSScriptRoot 'abnormal-response-common.ps1')

$kitRoot = Get-KitRoot
$targetRoot = Get-TargetRoot -Target $Target
$exe = Join-Path $targetRoot 'LhaForge.exe'
$config = Join-Path $targetRoot 'LhaForge.ini'
$evidenceRoot = Join-Path $kitRoot 'evidence-response-abnormal'
$beforePath = Join-Path $evidenceRoot 'state-before.json'

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
	throw 'Run initialize-response-abnormal-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
	throw ('LhaForge.exe was not found: {0}' -f $exe)
}

$caseDefinition = Get-Poc2C2AbnormalCase -CaseId $CaseId
$before = Read-JsonUtf8 -Path $beforePath
$runRuntime = Assert-Poc2C2AbnormalRuntime -ExpectedRuntime $before.runtime -KitRoot $kitRoot
$caseEvidence = Get-Poc2C2AbnormalCaseEvidence -State $before -CaseId $CaseId

$currentExe = Get-FileEvidence -Path $exe
$currentDll = Get-FileEvidence -Path (Join-Path $targetRoot '7-ZIP32.DLL')
if ([string]$currentExe.sha256 -cne [string]$before.targets.$Target.exe.sha256) {
	throw ('Target executable changed after abnormal initialization: {0}' -f $Target)
}
if ([string]$currentDll.sha256 -cne [string]$before.targets.$Target.dll.sha256) {
	throw ('Target DLL changed after abnormal initialization: {0}' -f $Target)
}

$inputEvidence = Get-FileHashEvidence -Path ([string]$before.fixture.input.path)
if (
	-not [bool]$inputEvidence.exists -or
	[string]$inputEvidence.sha256 -cne [string]$before.fixture.input.sha256 -or
	[Int64]$inputEvidence.sizeBytes -ne [Int64]$before.fixture.input.sizeBytes
) {
	throw 'Abnormal direct-input fixture changed after initialization.'
}

$recordPath = Get-Poc2C2AbnormalRunRecordPath -Target $Target -CaseId $CaseId
if ((Test-Path -LiteralPath $recordPath -PathType Leaf) -and -not $Force) {
	throw ('Abnormal run record already exists. Review it first, or use -Force only after diagnosing why a rerun is justified: {0}' -f $recordPath)
}

$caseRoot = Join-Path (Join-Path $targetRoot 'response-abnormal-results') $CaseId
if (Test-Path -LiteralPath $caseRoot) {
	if (-not $Force) {
		throw ('Case output already exists. Preserve it and review before rerunning, or use -Force only after diagnosis: {0}' -f $caseRoot)
	}
	Remove-Item -LiteralPath $caseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null

$workRoot = Join-Path $caseRoot 'response-work'
$outputRoot = Join-Path $caseRoot 'compressed'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$responseWork = Join-Path $workRoot 'a.rsp'
Copy-Item -LiteralPath ([string]$caseEvidence.responseFile.template.path) -Destination $responseWork -Force

$workingBefore = Get-Poc2C2RawFileEvidence -Path $responseWork
if (
	-not $workingBefore.exists -or
	[string]$workingBefore.sha256 -cne [string]$caseEvidence.responseFile.template.sha256 -or
	[Int64]$workingBefore.sizeBytes -ne [Int64]$caseEvidence.responseFile.template.sizeBytes
) {
	throw ('Abnormal response working copy does not match initialized template: {0}' -f $CaseId)
}

$archiveName = 'response-abnormal-' + $CaseId + '.zip'
$archive = Join-Path $outputRoot $archiveName

$args = @(
	(Quote-Poc2C2Argument ('/cfg:' + $config)),
	'/c:zip',
	(Quote-Poc2C2Argument ('/o:' + $outputRoot)),
	(Quote-Poc2C2Argument ('/f:' + $archiveName)),
	'/method:Deflate',
	'/level:5',
	'/popdir:yes',
	'/delete:no'
)

foreach ($token in $caseDefinition.argumentPlan) {
	if ($token -ceq 'direct-input') {
		$args += (Quote-Poc2C2Argument ([string]$before.fixture.input.path))
		continue
	}
	if ($token -ceq 'cp:invalid-value') {
		$args += '/cp:utf32'
		continue
	}
	if ($token -ceq 'cp:invalid-syntax') {
		$args += '/cpfoo'
		continue
	}
	if ($token -ceq 'cp:utf8') {
		$args += '/cp:utf8'
		continue
	}
	if ($token -ceq 'cp:utf16') {
		$args += '/cp:utf16'
		continue
	}
	if ($token -ceq 'response:a') {
		$prefix = if ([string]$caseDefinition.directive -ceq 'dollar') { '/$' } else { '/@' }
		$args += (Quote-Poc2C2Argument ($prefix + $responseWork))
		continue
	}
	throw ('Unknown abnormal C2 argument plan token: {0}' -f $token)
}

Write-Host ''
Write-Host ('[POC2-RSP-ABN] Target : {0}' -f $Target)
Write-Host ('[POC2-RSP-ABN] Case   : {0}' -f $CaseId)
Write-Host ('[POC2-RSP-ABN] Mode   : {0}' -f $caseDefinition.expectation.mode)
Write-Host ('[POC2-RSP-ABN] Reason : {0}' -f $caseDefinition.expectation.sourceRationale)
if ([bool]$caseDefinition.expectation.highRisk) {
	Write-Warning 'This is an odd-length UTF-16 boundary case. Run it only after the lower-risk abnormal cases and with a restorable VM snapshot.'
}
if ($caseDefinition.expectation.dialogExpected -eq $true) {
	Write-Host '[POC2-RSP-ABN] An LhaForge error dialog is expected. Read it, then close it with OK so the process can exit.'
}
else {
	Write-Host '[POC2-RSP-ABN] Observe whether any LhaForge dialog appears. Close it normally if one appears.'
}
Write-Host ''

$process = Invoke-Poc2C2AbnormalLhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args -TimeoutSeconds $TimeoutSeconds

$archiveFile = Get-FileHashEvidence -Path $archive
$archiveInventory = Get-Poc2C2AbnormalZipContentInventory -Path $archive
$responseAfter = Get-Poc2C2RawFileEvidence -Path $responseWork

$dialogObservation = if ([bool]$process.timedOut -or [bool]$process.looksLikeCrash) {
	'unknown'
}
elseif ($caseDefinition.expectation.dialogExpected -eq $true) {
	Read-Poc2C2DialogObservation -Prompt 'Did the expected LhaForge error dialog appear before the process exited?'
}
else {
	Read-Poc2C2DialogObservation -Prompt 'Did any LhaForge dialog appear before the process exited?'
}

$expectation = Test-Poc2C2AbnormalExpectation `
	-Case $caseDefinition `
	-Process $process `
	-ArchiveFile $archiveFile `
	-ResponseBefore $workingBefore `
	-ResponseAfter $responseAfter `
	-DialogObservation $dialogObservation

$behaviorSignature = Get-Poc2C2AbnormalBehaviorSignature `
	-Process $process `
	-ArchiveFile $archiveFile `
	-ArchiveInventory $archiveInventory `
	-ResponseAfter $responseAfter

$record = [ordered]@{
	schemaVersion = 1
	target = $Target
	operation = 'response-abnormal'
	caseId = $CaseId
	capturedUtc = [DateTime]::UtcNow.ToString('o')
	process = $process
	runtime = $runRuntime
	behaviorSignature = $behaviorSignature
	sourceExpectation = $caseDefinition.expectation
	expectationEvaluation = $expectation
	manual = [ordered]@{
		dialogObservation = $dialogObservation
	}
	details = [ordered]@{
		argumentPlan = @($caseDefinition.argumentPlan)
		arguments = @($args)
		inputFile = $inputEvidence
		archiveFile = $archiveFile
		archiveInventory = $archiveInventory
		responseFile = [ordered]@{
			key = 'a'
			fixtureKind = [string]$caseDefinition.fixtureKind
			directive = [string]$caseDefinition.directive
			workingBefore = $workingBefore
			workingAfter = $responseAfter
		}
	}
}

$path = Save-Poc2C2AbnormalRunRecord -Target $Target -CaseId $CaseId -Record $record

Write-Host ''
Write-Host ('[POC2-RSP-ABN] Evidence            : {0}' -f $path)
Write-Host ('[POC2-RSP-ABN] Behavior signature  : {0}' -f $behaviorSignature)
Write-Host ('[POC2-RSP-ABN] Archive exists      : {0}' -f $archiveFile.exists)
Write-Host ('[POC2-RSP-ABN] Response after run  : {0}' -f $(if ($responseAfter.exists) { 'preserved' } else { 'deleted' }))
Write-Host ('[POC2-RSP-ABN] Dialog observation  : {0}' -f $dialogObservation)

if ([string]$archiveInventory.parseStatus -ceq 'error') {
	throw ('Generated archive could not be parsed during abnormal case {0}. Evidence was saved. Stop and review before continuing. Parse error: {1}' -f $CaseId, $archiveInventory.parseError)
}
if ([bool]$process.timedOut) {
	throw ('LhaForge timed out during abnormal case {0}. Evidence was saved. Stop and review before continuing.' -f $CaseId)
}
if ([bool]$process.looksLikeCrash) {
	throw ('LhaForge appears to have crashed during abnormal case {0}: {1}. Evidence was saved. Stop and review before continuing.' -f $CaseId, $process.exitCodeHex)
}
if ([bool]$expectation.asserted -and -not [bool]$expectation.matched) {
	foreach ($issue in $expectation.issues) {
		Write-Host ('[POC2-RSP-ABN] EXPECTATION ISSUE: {0}' -f $issue)
	}
	throw ('Abnormal case differs from the source-derived expectation: {0}. Evidence was saved. Stop and review before continuing.' -f $CaseId)
}

if (-not [bool]$expectation.asserted) {
	Write-Host '[POC2-RSP-ABN] OBSERVE-ONLY case completed. Review the saved evidence before proceeding.'
}
else {
	Write-Host ('[POC2-RSP-ABN] {0}/response-abnormal/{1} matched the source-derived expectation.' -f $Target, $CaseId)
}
