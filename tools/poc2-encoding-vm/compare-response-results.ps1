#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'response-common.ps1')

function Get-Poc2C2CapturedRun {
	param(
		[Parameter(Mandatory = $true)]$Capture,
		[Parameter(Mandatory = $true)][string]$CaseId
	)

	$matches = @($Capture.runs | Where-Object {
		$_.operation -ceq 'response' -and [string]$_.caseId -ceq $CaseId
	})
	if ($matches.Count -ne 1) {
		throw ('Expected one C2 run record for {0}, found {1}.' -f $CaseId, $matches.Count)
	}
	return $matches[0]
}

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence-response'
$beforePath = Join-Path $evidenceRoot 'state-before.json'
$originalPath = Join-Path $evidenceRoot 'original-result.json'
$modernPath = Join-Path $evidenceRoot 'modern-result.json'

foreach ($path in @($beforePath, $originalPath, $modernPath)) {
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		throw ('Required C2 evidence is missing: {0}' -f $path)
	}
}

$before = Read-JsonUtf8 -Path $beforePath
$original = Read-JsonUtf8 -Path $originalPath
$modern = Read-JsonUtf8 -Path $modernPath

$issues = New-Object System.Collections.Generic.List[string]
$observations = New-Object System.Collections.Generic.List[string]
$identicalZipCount = 0
$caseCount = 0

if ([string]$original.dll.sha256 -cne [string]$modern.dll.sha256) {
	[void]$issues.Add('Original and Modern DLL hashes differ.')
}
if ([string]$original.dll.sha256 -cne [string]$before.sevenZipDllSha256) {
	[void]$issues.Add('Captured DLL hash differs from C2 initialization evidence.')
}
if ([int]$before.runtime.defaultEncodingCodePage -ne 932) {
	[void]$issues.Add(('C2 initialization ANSI code page was not 932: {0}' -f $before.runtime.defaultEncodingCodePage))
}
if ([int]$original.runtime.defaultEncodingCodePage -ne [int]$before.runtime.defaultEncodingCodePage) {
	[void]$issues.Add('Original capture ANSI code page differs from initialization.')
}
if ([int]$modern.runtime.defaultEncodingCodePage -ne [int]$before.runtime.defaultEncodingCodePage) {
	[void]$issues.Add('Modern capture ANSI code page differs from initialization.')
}

foreach ($case in Get-Poc2C2Cases) {
	$caseCount++
	$caseEvidence = Get-Poc2C2CaseEvidence -State $before -CaseId $case.id
	$o = Get-Poc2C2CapturedRun -Capture $original -CaseId $case.id
	$m = Get-Poc2C2CapturedRun -Capture $modern -CaseId $case.id

	$expectedPlan = (@($case.argumentPlan) -join "`n")
	$oPlan = (@($o.details.argumentPlan) -join "`n")
	$mPlan = (@($m.details.argumentPlan) -join "`n")
	if ($oPlan -cne $expectedPlan) {
		[void]$issues.Add(('Original C2 argument plan differs from the initialized case: {0}' -f $case.id))
	}
	if ($mPlan -cne $expectedPlan) {
		[void]$issues.Add(('Modern C2 argument plan differs from the initialized case: {0}' -f $case.id))
	}
	if ($oPlan -cne $mPlan) {
		[void]$issues.Add(('Original/Modern C2 argument plan differs: {0}' -f $case.id))
	}

	if (-not [bool]$o.success) {
		[void]$issues.Add(('Original C2 case did not pass: {0}' -f $case.id))
	}
	if (-not [bool]$m.success) {
		[void]$issues.Add(('Modern C2 case did not pass: {0}' -f $case.id))
	}
	if ([bool]$o.success -ne [bool]$m.success) {
		[void]$issues.Add(('Original/Modern C2 outcome differs: {0}' -f $case.id))
	}

	$expected = [string]$caseEvidence.expectedArchive.fingerprint
	$of = [string]$o.details.archiveInventory.fingerprint
	$mf = [string]$m.details.archiveInventory.fingerprint

	if ($of -cne $expected) {
		[void]$issues.Add(('Original C2 archive differs from expected input set: {0}' -f $case.id))
	}
	if ($mf -cne $expected) {
		[void]$issues.Add(('Modern C2 archive differs from expected input set: {0}' -f $case.id))
	}
	if ($of -cne $mf) {
		[void]$issues.Add(('Original/Modern C2 archive content fingerprint differs: {0}' -f $case.id))
	}

	$oZip = [string]$o.details.archiveFile.sha256
	$mZip = [string]$m.details.archiveFile.sha256
	if (-not [string]::IsNullOrWhiteSpace($oZip) -and $oZip -ceq $mZip) {
		$identicalZipCount++
	}

	$expectedResponses = @($caseEvidence.responseFiles)
	$oResponses = @($o.details.responseFiles)
	$mResponses = @($m.details.responseFiles)
	if (
		$oResponses.Count -ne $expectedResponses.Count -or
		$mResponses.Count -ne $expectedResponses.Count
	) {
		[void]$issues.Add(('Captured response file count differs from the initialized case: {0}' -f $case.id))
	}
	else {
		for ($i = 0; $i -lt $expectedResponses.Count; $i++) {
			$expectedResponse = $expectedResponses[$i]
			$or = $oResponses[$i]
			$mr = $mResponses[$i]

			if ([string]$or.key -cne [string]$expectedResponse.key) {
				[void]$issues.Add(('Original response key differs from initialized evidence: {0}/{1}' -f $case.id, $expectedResponse.key))
			}
			if ([string]$mr.key -cne [string]$expectedResponse.key) {
				[void]$issues.Add(('Modern response key differs from initialized evidence: {0}/{1}' -f $case.id, $expectedResponse.key))
			}
			foreach ($capturedResponse in @($or, $mr)) {
				if (
					-not [bool]$capturedResponse.workingBefore.exists -or
					[string]$capturedResponse.workingBefore.sha256 -cne [string]$expectedResponse.template.sha256 -or
					[Int64]$capturedResponse.workingBefore.sizeBytes -ne [Int64]$expectedResponse.template.sizeBytes
				) {
					[void]$issues.Add(('Response raw identity differs from initialized template: {0}/{1}/{2}' -f $case.id, $expectedResponse.key, $capturedResponse.key))
				}
				if (
					[string]$capturedResponse.encoding -cne [string]$expectedResponse.encoding -or
					[bool]$capturedResponse.bom -ne [bool]$expectedResponse.bom -or
					[string]$capturedResponse.newline -cne [string]$expectedResponse.newline -or
					[string]$capturedResponse.directive -cne [string]$expectedResponse.directive
				) {
					[void]$issues.Add(('Response metadata differs from initialized evidence: {0}/{1}/{2}' -f $case.id, $expectedResponse.key, $capturedResponse.key))
				}
			}

			if ([string]$or.workingBefore.sha256 -cne [string]$mr.workingBefore.sha256) {
				[void]$issues.Add(('Original/Modern response raw SHA-256 differs: {0}/{1}' -f $case.id, $expectedResponse.key))
			}
			if ([bool]$or.workingAfter.exists -ne [bool]$mr.workingAfter.exists) {
				[void]$issues.Add(('Original/Modern response post-state differs: {0}/{1}' -f $case.id, $or.key))
			}
			if ([string]$or.directive -ceq 'at') {
				if (-not [bool]$or.workingAfter.exists -or -not [bool]$mr.workingAfter.exists) {
					[void]$issues.Add(('Response file was not preserved for /@ case: {0}/{1}' -f $case.id, $or.key))
				}
			}
			elseif ([string]$or.directive -ceq 'dollar') {
				if ([bool]$or.workingAfter.exists -or [bool]$mr.workingAfter.exists) {
					[void]$issues.Add(('Response file was not deleted for /$ case: {0}/{1}' -f $case.id, $or.key))
				}
			}
		}
	}
}

if (-not (Test-ExternalInventoryEqual -Left $before.external -Right $original.external)) {
	[void]$issues.Add('Original changed external AppData/ProgramData state during C2.')
}
if (-not (Test-ExternalInventoryEqual -Left $before.external -Right $modern.external)) {
	[void]$issues.Add('Modern changed external AppData/ProgramData state during C2.')
}

[void]$observations.Add(('{0} of {1} generated ZIP byte SHA-256 pairs are identical.' -f $identicalZipCount, $caseCount))
$classification = if ($issues.Count -eq 0) { 'MATCH' } else { 'REVIEW_REQUIRED' }

$report = [ordered]@{
	schemaVersion = 1
	generatedUtc = [DateTime]::UtcNow.ToString('o')
	classification = $classification
	issueCount = $issues.Count
	issues = @($issues)
	observations = @($observations)
	caseCount = $caseCount
	identicalZipByteHashCount = $identicalZipCount
	ansiCodePage = [int]$before.runtime.defaultEncodingCodePage
	originalExeSha256 = [string]$original.exe.sha256
	modernExeSha256 = [string]$modern.exe.sha256
	sevenZipDllSha256 = [string]$original.dll.sha256
}

$reportPath = Join-Path $evidenceRoot 'comparison.json'
Write-JsonUtf8NoBom -Value $report -Path $reportPath -Depth 14

Write-Host ''
Write-Host ('[POC2-RSP] Classification: {0}' -f $classification)
foreach ($item in $observations) {
	Write-Host ('[POC2-RSP] OBS: {0}' -f $item)
}
foreach ($item in $issues) {
	Write-Host ('[POC2-RSP] ISSUE: {0}' -f $item)
}
Write-Host ('[POC2-RSP] Report: {0}' -f $reportPath)

if ($issues.Count -ne 0) {
	exit 2
}
