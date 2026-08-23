#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'response-common.ps1')
. (Join-Path $PSScriptRoot 'abnormal-response-common.ps1')

function Get-Poc2C2AbnormalCapturedRun {
	param(
		[Parameter(Mandatory = $true)]$Capture,
		[Parameter(Mandatory = $true)][string]$CaseId
	)

	$matches = @($Capture.runs | Where-Object {
		$_.operation -ceq 'response-abnormal' -and [string]$_.caseId -ceq $CaseId
	})
	if ($matches.Count -ne 1) {
		throw ('Expected one abnormal C2 run record for {0}, found {1}.' -f $CaseId, $matches.Count)
	}
	return $matches[0]
}

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence-response-abnormal'
$beforePath = Join-Path $evidenceRoot 'state-before.json'
$originalPath = Join-Path $evidenceRoot 'original-result.json'
$modernPath = Join-Path $evidenceRoot 'modern-result.json'

foreach ($path in @($beforePath, $originalPath, $modernPath)) {
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		throw ('Required abnormal C2 evidence is missing: {0}' -f $path)
	}
}

$before = Read-JsonUtf8 -Path $beforePath
[void](Assert-Poc2C2AbnormalRuntime -ExpectedRuntime $before.runtime -KitRoot $kitRoot)
$original = Read-JsonUtf8 -Path $originalPath
$modern = Read-JsonUtf8 -Path $modernPath

$issues = New-Object System.Collections.Generic.List[string]
$observations = New-Object System.Collections.Generic.List[string]
$securityCaseIds = New-Object System.Collections.Generic.List[string]
$caseCount = 0

if ([string]$original.exe.sha256 -cne [string]$before.targets.original.exe.sha256) {
	[void]$issues.Add('Original executable hash differs from abnormal initialization evidence.')
}
if ([string]$modern.exe.sha256 -cne [string]$before.targets.modern.exe.sha256) {
	[void]$issues.Add('Modern executable hash differs from abnormal initialization evidence.')
}
if ([string]$original.dll.sha256 -cne [string]$modern.dll.sha256) {
	[void]$issues.Add('Original and Modern DLL hashes differ.')
}
if ([string]$original.dll.sha256 -cne [string]$before.sevenZipDllSha256) {
	[void]$issues.Add('Captured DLL hash differs from abnormal C2 initialization evidence.')
}
if ([int]$before.runtime.defaultEncodingCodePage -ne 932) {
	[void]$issues.Add(('Abnormal C2 initialization ANSI code page was not 932: {0}' -f $before.runtime.defaultEncodingCodePage))
}
if ([int]$original.runtime.defaultEncodingCodePage -ne [int]$before.runtime.defaultEncodingCodePage) {
	[void]$issues.Add('Original capture ANSI code page differs from initialization.')
}
if ([int]$modern.runtime.defaultEncodingCodePage -ne [int]$before.runtime.defaultEncodingCodePage) {
	[void]$issues.Add('Modern capture ANSI code page differs from initialization.')
}

foreach ($case in Get-Poc2C2AbnormalCases) {
	$caseCount++
	if ([string]$case.expectation.securityDisposition -ceq 'security-change-required') {
		[void]$securityCaseIds.Add([string]$case.id)
	}
	$caseEvidence = Get-Poc2C2AbnormalCaseEvidence -State $before -CaseId $case.id
	$o = Get-Poc2C2AbnormalCapturedRun -Capture $original -CaseId $case.id
	$m = Get-Poc2C2AbnormalCapturedRun -Capture $modern -CaseId $case.id

	$expectedPlan = (@($case.argumentPlan) -join "`n")
	$oPlan = (@($o.details.argumentPlan) -join "`n")
	$mPlan = (@($m.details.argumentPlan) -join "`n")
	if ($oPlan -cne $expectedPlan) {
		[void]$issues.Add(('Original abnormal C2 argument plan differs from initialized case: {0}' -f $case.id))
	}
	if ($mPlan -cne $expectedPlan) {
		[void]$issues.Add(('Modern abnormal C2 argument plan differs from initialized case: {0}' -f $case.id))
	}

	foreach ($pair in @(
		[pscustomobject]@{ name = 'Original'; run = $o },
		[pscustomobject]@{ name = 'Modern'; run = $m }
	)) {
		$run = $pair.run
		$response = $run.details.responseFile

		foreach ($name in @('psEdition', 'powerShellVersion', 'defaultEncodingCodePage', 'currentCulture', 'currentUICulture')) {
			if ([string]$run.runtime.$name -cne [string]$before.runtime.$name) {
				[void]$issues.Add(('{0} abnormal run runtime differs from initialization for {1}/{2}.' -f $pair.name, $case.id, $name))
			}
		}

		if (
			-not [bool]$run.details.inputFile.exists -or
			[string]$run.details.inputFile.sha256 -cne [string]$before.fixture.input.sha256 -or
			[Int64]$run.details.inputFile.sizeBytes -ne [Int64]$before.fixture.input.sizeBytes
		) {
			[void]$issues.Add(('{0} abnormal direct-input fixture identity differs from initialization: {1}' -f $pair.name, $case.id))
		}

		if (
			-not [bool]$response.workingBefore.exists -or
			[string]$response.workingBefore.sha256 -cne [string]$caseEvidence.responseFile.template.sha256 -or
			[Int64]$response.workingBefore.sizeBytes -ne [Int64]$caseEvidence.responseFile.template.sizeBytes
		) {
			[void]$issues.Add(('{0} abnormal response raw identity differs from initialized template: {1}' -f $pair.name, $case.id))
		}

		if ([bool]$run.process.timedOut) {
			[void]$issues.Add(('{0} abnormal C2 case timed out: {1}' -f $pair.name, $case.id))
		}
		if ([bool]$run.process.looksLikeCrash) {
			[void]$issues.Add(('{0} abnormal C2 case looks like a crash: {1}/{2}' -f $pair.name, $case.id, $run.process.exitCodeHex))
		}

		if ([string]$case.expectation.mode -ceq 'asserted') {
			if (-not [bool]$run.expectationEvaluation.asserted -or -not [bool]$run.expectationEvaluation.matched) {
				[void]$issues.Add(('{0} abnormal C2 case did not match the source-derived expectation: {1}' -f $pair.name, $case.id))
			}
		}
	}

	if ([string]$o.behaviorSignature -cne [string]$m.behaviorSignature) {
		[void]$issues.Add(('Original/Modern abnormal behavior signature differs: {0}' -f $case.id))
	}

	if ([bool]$o.details.responseFile.workingAfter.exists -ne [bool]$m.details.responseFile.workingAfter.exists) {
		[void]$issues.Add(('Original/Modern abnormal response post-state differs: {0}' -f $case.id))
	}
	elseif ([bool]$o.details.responseFile.workingAfter.exists) {
		if ([string]$o.details.responseFile.workingAfter.sha256 -cne [string]$m.details.responseFile.workingAfter.sha256) {
			[void]$issues.Add(('Original/Modern preserved abnormal response SHA-256 differs: {0}' -f $case.id))
		}
	}

	if ([bool]$o.details.archiveFile.exists -ne [bool]$m.details.archiveFile.exists) {
		[void]$issues.Add(('Original/Modern abnormal archive existence differs: {0}' -f $case.id))
	}
	elseif ([bool]$o.details.archiveFile.exists) {
		if ([string]$o.details.archiveInventory.parseStatus -ceq 'error') {
			[void]$issues.Add(('Original abnormal archive inventory could not be parsed: {0}' -f $case.id))
		}
		if ([string]$m.details.archiveInventory.parseStatus -ceq 'error') {
			[void]$issues.Add(('Modern abnormal archive inventory could not be parsed: {0}' -f $case.id))
		}
		if ([string]$o.details.archiveInventory.parseStatus -cne [string]$m.details.archiveInventory.parseStatus) {
			[void]$issues.Add(('Original/Modern abnormal archive parse status differs: {0}' -f $case.id))
		}
		if ([string]$o.details.archiveInventory.fingerprint -cne [string]$m.details.archiveInventory.fingerprint) {
			[void]$issues.Add(('Original/Modern abnormal archive content fingerprint differs: {0}' -f $case.id))
		}
	}

	$oDialog = [string]$o.manual.dialogObservation
	$mDialog = [string]$m.manual.dialogObservation
	if ($oDialog -ceq 'unknown' -or $mDialog -ceq 'unknown') {
		[void]$issues.Add(('Dialog observation is unknown and requires review: {0} (Original={1}, Modern={2})' -f $case.id, $oDialog, $mDialog))
	}
	elseif ($oDialog -cne $mDialog) {
		[void]$issues.Add(('Original/Modern dialog observation differs: {0} (Original={1}, Modern={2})' -f $case.id, $oDialog, $mDialog))
	}

	if ([string]$case.expectation.mode -ceq 'observe-only') {
		[void]$observations.Add(('Observe-only case {0}: Original signature {1}; Modern signature {2}.' -f $case.id, $o.behaviorSignature, $m.behaviorSignature))
	}
}

if (-not (Test-ExternalInventoryEqual -Left $before.external -Right $original.external)) {
	[void]$issues.Add('Original changed external AppData/ProgramData state during abnormal C2.')
}
if (-not (Test-ExternalInventoryEqual -Left $before.external -Right $modern.external)) {
	[void]$issues.Add('Modern changed external AppData/ProgramData state during abnormal C2.')
}
if (-not (Test-Poc2C2TempZipStateEqual -Left $before.tempZip -Right $original.tempZip)) {
	[void]$issues.Add('Original changed tracked TEMP zip*.tmp state during abnormal C2.')
}
if (-not (Test-Poc2C2TempZipStateEqual -Left $before.tempZip -Right $modern.tempZip)) {
	[void]$issues.Add('Modern changed tracked TEMP zip*.tmp state during abnormal C2.')
}

if ($securityCaseIds.Count -ne 0) {
	[void]$observations.Add(('Source-level safety hardening is required for: {0}.' -f (@($securityCaseIds) -join ', ')))
}

$classification = if ($issues.Count -ne 0) {
	'REVIEW_REQUIRED'
}
elseif ($securityCaseIds.Count -ne 0) {
	'SECURITY_CHANGE_REQUIRED'
}
else {
	'MATCH'
}

$report = [ordered]@{
	schemaVersion = 1
	generatedUtc = [DateTime]::UtcNow.ToString('o')
	classification = $classification
	issueCount = $issues.Count
	issues = @($issues)
	observations = @($observations)
	securityCaseIds = @($securityCaseIds)
	caseCount = $caseCount
	ansiCodePage = [int]$before.runtime.defaultEncodingCodePage
	repoHead = [string]$before.repoHead
	originalExeSha256 = [string]$original.exe.sha256
	modernExeSha256 = [string]$modern.exe.sha256
	sevenZipDllSha256 = [string]$original.dll.sha256
}

$reportPath = Join-Path $evidenceRoot 'comparison.json'
Write-JsonUtf8NoBom -Value $report -Path $reportPath -Depth 16

Write-Host ''
Write-Host ('[POC2-RSP-ABN] Classification: {0}' -f $classification)
foreach ($item in $observations) {
	Write-Host ('[POC2-RSP-ABN] OBS: {0}' -f $item)
}
foreach ($item in $issues) {
	Write-Host ('[POC2-RSP-ABN] ISSUE: {0}' -f $item)
}
Write-Host ('[POC2-RSP-ABN] Report: {0}' -f $reportPath)

if ($issues.Count -ne 0) {
	exit 2
}
