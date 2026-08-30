#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'c3-common.ps1')

function Get-C3Run {
    param(
        [Parameter(Mandatory = $true)]$Capture,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$CaseId
    )

    $matches = @($Capture.runs | Where-Object {
        [string]$_.operation -ceq $Operation -and [string]$_.caseId -ceq $CaseId
    })
    if ($matches.Count -ne 1) {
        throw ('Expected one C3 run record for {0}/{1}, found {2}.' -f $Operation, $CaseId, $matches.Count)
    }
    return $matches[0]
}

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence-c3'
$beforePath = Join-Path $evidenceRoot 'state-before-c3.json'
$originalPath = Join-Path $evidenceRoot 'original-c3-result.json'
$modernPath = Join-Path $evidenceRoot 'modern-c3-result.json'

foreach ($path in @($beforePath, $originalPath, $modernPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Required C3 evidence is missing: {0}' -f $path)
    }
}

$before = Read-JsonUtf8 -Path $beforePath
$original = Read-JsonUtf8 -Path $originalPath
$modern = Read-JsonUtf8 -Path $modernPath

$issues = New-Object System.Collections.Generic.List[string]
$observations = New-Object System.Collections.Generic.List[string]
$regressionDifferences = New-Object System.Collections.Generic.List[string]
$reviewDifferences = New-Object System.Collections.Generic.List[string]
$unknowns = New-Object System.Collections.Generic.List[string]

function Add-C3ParityDifference {
    param(
        [Parameter(Mandatory = $true)]$Case,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ([string]$Case.behaviorClass -in @('spec-valid', 'cross-platform-observe')) {
        [void]$regressionDifferences.Add($Message)
    }
    else {
        [void]$reviewDifferences.Add($Message)
    }
}

if ([string]$original.dll.sha256 -cne [string]$modern.dll.sha256) {
    [void]$issues.Add('Original and Modern DLL hashes differ.')
}
if ([string]$original.dll.sha256 -cne [string]$before.sevenZipDllSha256) {
    [void]$issues.Add('Captured DLL hash differs from initialization evidence.')
}

foreach ($case in Get-Poc2C3FrozenCases) {
    foreach ($op in @('list', 'test')) {
        $o = Get-C3Run -Capture $original -Operation $op -CaseId $case.id
        $m = Get-C3Run -Capture $modern -Operation $op -CaseId $case.id

        if ([string]$o.observationKey -cne [string]$m.observationKey) {
            Add-C3ParityDifference -Case $case -Message ('{0}/{1} observation differs: Original={2}, Modern={3}' -f $case.id, $op, $o.observationKey, $m.observationKey)
        }
        if ([string]$o.process.exitCodeHex -cne [string]$m.process.exitCodeHex) {
            Add-C3ParityDifference -Case $case -Message ('{0}/{1} process exit differs: Original={2}, Modern={3}' -f $case.id, $op, $o.process.exitCodeHex, $m.process.exitCodeHex)
        }
        if ([string]$o.observationKey -ceq 'other' -or [string]$m.observationKey -ceq 'other') {
            [void]$unknowns.Add(('{0}/{1} contains manual "other" observation.' -f $case.id, $op))
        }
    }

    $oe = Get-C3Run -Capture $original -Operation 'extract' -CaseId $case.id
    $me = Get-C3Run -Capture $modern -Operation 'extract' -CaseId $case.id

    if ([string]$oe.observationKey -cne [string]$me.observationKey) {
        Add-C3ParityDifference -Case $case -Message ('{0}/extract UI observation differs: Original={1}, Modern={2}' -f $case.id, $oe.observationKey, $me.observationKey)
    }
    if ([string]$oe.process.exitCodeHex -cne [string]$me.process.exitCodeHex) {
        Add-C3ParityDifference -Case $case -Message ('{0}/extract process exit differs: Original={1}, Modern={2}' -f $case.id, $oe.process.exitCodeHex, $me.process.exitCodeHex)
    }

    $of = [string]$oe.details.inventory.fingerprint
    $mf = [string]$me.details.inventory.fingerprint
    if ($of -cne $mf) {
        Add-C3ParityDifference -Case $case -Message ('{0}/extract filesystem fingerprint differs.' -f $case.id)
    }

    if ($case.behaviorClass -in @('spec-valid', 'cross-platform-observe')) {
        if ([string](Get-C3Run -Capture $original -Operation 'test' -CaseId $case.id).observationKey -cne 'success') {
            [void]$issues.Add(('Original valid fixture test did not report success: {0}' -f $case.id))
        }
        if ([string](Get-C3Run -Capture $modern -Operation 'test' -CaseId $case.id).observationKey -cne 'success') {
            [void]$issues.Add(('Modern valid fixture test did not report success: {0}' -f $case.id))
        }

        if ($null -ne $oe.details.semanticMatch -and -not [bool]$oe.details.semanticMatch) {
            [void]$issues.Add(('Original valid fixture extraction differs from declared semantic inventory: {0}' -f $case.id))
        }
        if ($null -ne $me.details.semanticMatch -and -not [bool]$me.details.semanticMatch) {
            [void]$issues.Add(('Modern valid fixture extraction differs from declared semantic inventory: {0}' -f $case.id))
        }
    }

    [void]$observations.Add(('{0}: list={1}, test={2}, extractFingerprint={3}' -f
        $case.id,
        (Get-C3Run -Capture $original -Operation 'list' -CaseId $case.id).observationKey,
        (Get-C3Run -Capture $original -Operation 'test' -CaseId $case.id).observationKey,
        $of))
}

foreach ($capture in @($original, $modern)) {
    if (-not (Test-ExternalInventoryEqual -Left $before.external -Right $capture.external)) {
        [void]$issues.Add(('{0} changed external AppData/ProgramData state.' -f $capture.target))
    }
}

$classification = 'MATCH'
if ($regressionDifferences.Count -ne 0) {
    $classification = 'REGRESSION'
}
elseif ($issues.Count -ne 0 -or $reviewDifferences.Count -ne 0 -or $unknowns.Count -ne 0) {
    $classification = 'UNKNOWN'
}

$report = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    classification = $classification
    issueCount = $issues.Count
    issues = @($issues)
    regressionDifferenceCount = $regressionDifferences.Count
    regressionDifferences = @($regressionDifferences)
    reviewDifferenceCount = $reviewDifferences.Count
    reviewDifferences = @($reviewDifferences)
    unknownCount = $unknowns.Count
    unknowns = @($unknowns)
    observations = @($observations)
    originalExeSha256 = [string]$original.exe.sha256
    modernExeSha256 = [string]$modern.exe.sha256
    sevenZipDllSha256 = [string]$original.dll.sha256
    fixtureManifestSha256 = [string]$before.fixtureManifestSha256
}

$reportPath = Join-Path $evidenceRoot 'comparison-c3.json'
Write-JsonUtf8NoBom -Value $report -Path $reportPath -Depth 24

Write-Host ''
Write-Host ('[POC2-C3] Classification: {0}' -f $classification)
foreach ($item in $regressionDifferences) { Write-Host ('[POC2-C3] REGRESSION: {0}' -f $item) }
foreach ($item in $reviewDifferences) { Write-Host ('[POC2-C3] REVIEW: {0}' -f $item) }
foreach ($item in $issues) { Write-Host ('[POC2-C3] ISSUE: {0}' -f $item) }
foreach ($item in $unknowns) { Write-Host ('[POC2-C3] UNKNOWN: {0}' -f $item) }
Write-Host ('[POC2-C3] Report: {0}' -f $reportPath)

if ($classification -cne 'MATCH') {
    exit 2
}
