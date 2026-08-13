#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')

function Get-Run {
    param(
        [Parameter(Mandatory = $true)]$Capture,
        [Parameter(Mandatory = $true)][string]$Operation,
        [string]$CaseId
    )

    $matches = @($Capture.runs | Where-Object {
        $_.operation -ceq $Operation -and (
            ([string]::IsNullOrWhiteSpace($CaseId) -and $null -eq $_.caseId) -or
            (-not [string]::IsNullOrWhiteSpace($CaseId) -and [string]$_.caseId -ceq $CaseId)
        )
    })
    if ($matches.Count -ne 1) {
        throw ('Expected one run record for {0}/{1}, found {2}.' -f $Operation, $CaseId, $matches.Count)
    }
    return $matches[0]
}

$kitRoot = Get-KitRoot
$evidenceRoot = Join-Path $kitRoot 'evidence'
$beforePath = Join-Path $evidenceRoot 'state-before.json'
$originalPath = Join-Path $evidenceRoot 'original-result.json'
$modernPath = Join-Path $evidenceRoot 'modern-result.json'

foreach ($path in @($beforePath, $originalPath, $modernPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Required evidence is missing: {0}' -f $path)
    }
}

$before = Read-JsonUtf8 -Path $beforePath
$original = Read-JsonUtf8 -Path $originalPath
$modern = Read-JsonUtf8 -Path $modernPath

$issues = New-Object System.Collections.Generic.List[string]
$observations = New-Object System.Collections.Generic.List[string]

if ([string]$original.dll.sha256 -cne [string]$modern.dll.sha256) {
    [void]$issues.Add('Original and Modern DLL hashes differ.')
}
if ([string]$original.dll.sha256 -cne [string]$before.sevenZipDllSha256) {
    [void]$issues.Add('Captured DLL hash differs from initialization evidence.')
}

foreach ($op in @('list', 'test')) {
    $o = Get-Run -Capture $original -Operation $op
    $m = Get-Run -Capture $modern -Operation $op
    if (-not [bool]$o.success) { [void]$issues.Add(('Original {0} did not pass.' -f $op)) }
    if (-not [bool]$m.success) { [void]$issues.Add(('Modern {0} did not pass.' -f $op)) }
    if ([bool]$o.success -ne [bool]$m.success) {
        [void]$issues.Add(('Original/Modern {0} outcome differs.' -f $op))
    }
}

foreach ($case in Get-Poc2C1Cases) {
    $o = Get-Run -Capture $original -Operation 'pathprobe' -CaseId $case.id
    $m = Get-Run -Capture $modern -Operation 'pathprobe' -CaseId $case.id

    if (-not [bool]$o.success) { [void]$issues.Add(('Original pathprobe failed: {0}' -f $case.id)) }
    if (-not [bool]$m.success) { [void]$issues.Add(('Modern pathprobe failed: {0}' -f $case.id)) }

    $of = [string]$o.details.actualInventory.fingerprint
    $mf = [string]$m.details.actualInventory.fingerprint
    if ($of -cne $mf) {
        [void]$issues.Add(('Pathprobe fingerprint differs: {0}' -f $case.id))
    }

    $expected = [string]$before.fixture.inputInventory.fingerprint
    if ($of -cne $expected) {
        [void]$issues.Add(('Original pathprobe differs from fixture: {0}' -f $case.id))
    }
    if ($mf -cne $expected) {
        [void]$issues.Add(('Modern pathprobe differs from fixture: {0}' -f $case.id))
    }
}

$oCompress = Get-Run -Capture $original -Operation 'compress'
$mCompress = Get-Run -Capture $modern -Operation 'compress'
if (-not [bool]$oCompress.success) { [void]$issues.Add('Original compress did not pass.') }
if (-not [bool]$mCompress.success) { [void]$issues.Add('Modern compress did not pass.') }

$oArchiveFp = [string]$oCompress.details.archiveEntries.fileFingerprint
$mArchiveFp = [string]$mCompress.details.archiveEntries.fileFingerprint
if ($oArchiveFp -cne $mArchiveFp) {
    [void]$issues.Add('Original/Modern compressed ZIP filename semantics differ.')
}

$expectedArchiveFp = [string]$before.fixture.inputInventory.archiveSemanticFingerprint
if ($oArchiveFp -cne $expectedArchiveFp) {
    [void]$issues.Add('Original compressed ZIP filename semantics differ from fixture.')
}
if ($mArchiveFp -cne $expectedArchiveFp) {
    [void]$issues.Add('Modern compressed ZIP filename semantics differ from fixture.')
}

$oZipHash = [string]$oCompress.details.archiveFile.sha256
$mZipHash = [string]$mCompress.details.archiveFile.sha256
if ($oZipHash -ceq $mZipHash) {
    [void]$observations.Add('Compressed ZIP byte SHA-256 is identical.')
}
else {
    [void]$observations.Add('Compressed ZIP byte SHA-256 differs; semantic comparison remains primary evidence.')
}

foreach ($capture in @($original, $modern)) {
    $target = [string]$capture.target
    $reextract = Get-Run -Capture $capture -Operation 'reextract'
    if (-not [bool]$reextract.success) {
        [void]$issues.Add(('{0} reextract did not pass.' -f $target))
    }

    $actual = [string]$reextract.details.actualInventory.fingerprint
    $expected = [string]$before.fixture.inputInventory.fingerprint
    if ($actual -cne $expected) {
        [void]$issues.Add(('{0} reextract differs from fixture payload/name fingerprint.' -f $target))
    }

    if (-not (Test-ExternalInventoryEqual -Left $before.external -Right $capture.external)) {
        [void]$issues.Add(('{0} changed external AppData/ProgramData state.' -f $target))
    }
}

$classification = if ($issues.Count -eq 0) { 'MATCH' } else { 'REVIEW_REQUIRED' }

$report = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    classification = $classification
    issueCount = $issues.Count
    issues = @($issues)
    observations = @($observations)
    originalExeSha256 = [string]$original.exe.sha256
    modernExeSha256 = [string]$modern.exe.sha256
    sevenZipDllSha256 = [string]$original.dll.sha256
    referenceZipSha256 = [string]$before.fixture.referenceZip.sha256
}
$reportPath = Join-Path $evidenceRoot 'comparison.json'
Write-JsonUtf8NoBom -Value $report -Path $reportPath -Depth 12

Write-Host ''
Write-Host ('[POC2-ENC] Classification: {0}' -f $classification)
foreach ($item in $observations) {
    Write-Host ('[POC2-ENC] OBS: {0}' -f $item)
}
foreach ($item in $issues) {
    Write-Host ('[POC2-ENC] ISSUE: {0}' -f $item)
}
Write-Host ('[POC2-ENC] Report: {0}' -f $reportPath)

if ($issues.Count -ne 0) {
    exit 2
}
