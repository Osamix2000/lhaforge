#Requires -Version 5.1
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidateSet('original', 'modern')]
	[string]$Target,

	[Parameter(Mandatory = $true)]
	[string]$CaseId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'response-common.ps1')

$kitRoot = Get-KitRoot
$targetRoot = Get-TargetRoot -Target $Target
$exe = Join-Path $targetRoot 'LhaForge.exe'
$config = Join-Path $targetRoot 'LhaForge.ini'
$evidenceRoot = Join-Path $kitRoot 'evidence-response'
$beforePath = Join-Path $evidenceRoot 'state-before.json'

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
	throw 'Run initialize-response-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
	throw ('LhaForge.exe was not found: {0}' -f $exe)
}

$caseDefinition = Get-Poc2C2Case -CaseId $CaseId
$before = Read-JsonUtf8 -Path $beforePath
$caseEvidence = Get-Poc2C2CaseEvidence -State $before -CaseId $CaseId

$caseRoot = Join-Path (Join-Path $targetRoot 'response-results') $CaseId
if (Test-Path -LiteralPath $caseRoot) {
	Remove-Item -LiteralPath $caseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null

$workRoot = Join-Path $caseRoot 'response-work'
$outputRoot = Join-Path $caseRoot 'compressed'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$responseWork = @{}
$responseState = @()
foreach ($initializedSpec in $caseEvidence.responseFiles) {
	$key = [string]$initializedSpec.key
	$workPath = Join-Path $workRoot ($key + '.rsp')
	Copy-Item -LiteralPath ([string]$initializedSpec.template.path) -Destination $workPath -Force
	$responseWork[$key] = $workPath

	$workingBefore = Get-Poc2C2RawFileEvidence -Path $workPath
	if (
		-not $workingBefore.exists -or
		[string]$workingBefore.sha256 -cne [string]$initializedSpec.template.sha256 -or
		[Int64]$workingBefore.sizeBytes -ne [Int64]$initializedSpec.template.sizeBytes
	) {
		throw ('Response working copy does not match the initialized template: {0}/{1}' -f $CaseId, $key)
	}

	$responseState += [ordered]@{
		key = $key
		encoding = [string]$initializedSpec.encoding
		bom = [bool]$initializedSpec.bom
		newline = [string]$initializedSpec.newline
		inputIds = @($initializedSpec.inputIds)
		directive = [string]$initializedSpec.directive
		template = $initializedSpec.template
		workingBefore = $workingBefore
		workingAfter = $null
	}
}

$archiveName = 'response-' + $CaseId + '.zip'
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
	if ($token -ceq 'cp:sjis') {
		$args += '/cp:sjis'
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
	if ($token -ceq 'cp:reset') {
		$args += '/cp'
		continue
	}
	if ($token.StartsWith('response:', [System.StringComparison]::Ordinal)) {
		$key = $token.Substring('response:'.Length)
		if (-not $responseWork.ContainsKey($key)) {
			throw ('Response plan references unknown key {0}.' -f $key)
		}
		$initializedMatches = @($caseEvidence.responseFiles | Where-Object { $_.key -ceq $key })
		if ($initializedMatches.Count -ne 1) {
			throw ('Expected one initialized response spec for key {0}.' -f $key)
		}
		$prefix = if ([string]$initializedMatches[0].directive -ceq 'dollar') { '/$' } else { '/@' }
		$args += (Quote-Poc2C2Argument ($prefix + [string]$responseWork[$key]))
		continue
	}
	throw ('Unknown C2 argument plan token: {0}' -f $token)
}

$process = Invoke-Poc2C2LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
$archiveFile = Get-FileHashEvidence -Path $archive
$archiveInventory = Get-Poc2C2ZipContentInventory -Path $archive

$responseOk = $true
for ($i = 0; $i -lt $responseState.Count; $i++) {
	$item = $responseState[$i]
	$workPath = [string]$responseWork[[string]$item.key]
	$after = Get-Poc2C2RawFileEvidence -Path $workPath
	$item.workingAfter = $after

	if ([string]$item.directive -ceq 'dollar') {
		if ($after.exists) { $responseOk = $false }
	}
	else {
		if (-not $after.exists) {
			$responseOk = $false
		}
		elseif ([string]$after.sha256 -cne [string]$item.workingBefore.sha256) {
			$responseOk = $false
		}
	}
}

$expectedFingerprint = [string]$caseEvidence.expectedArchive.fingerprint
$archiveOk = (
	$archiveFile.exists -and
	$archiveInventory.exists -and
	([string]$archiveInventory.fingerprint -ceq $expectedFingerprint)
)
$passed = (
	-not $process.looksLikeCrash -and
	$process.exitCode -eq 0 -and
	$archiveOk -and
	$responseOk
)

$record = [ordered]@{
	schemaVersion = 1
	target = $Target
	operation = 'response'
	caseId = $CaseId
	capturedUtc = [DateTime]::UtcNow.ToString('o')
	process = $process
	success = $passed
	details = [ordered]@{
		argumentPlan = @($caseDefinition.argumentPlan)
		arguments = @($args)
		expectedInputIds = @($caseEvidence.expectedInputIds)
		expectedArchiveFingerprint = $expectedFingerprint
		archiveFile = $archiveFile
		archiveInventory = $archiveInventory
		responseFiles = @($responseState)
	}
}

$path = Save-Poc2C2RunRecord -Target $Target -CaseId $CaseId -Record $record
Write-Host ('[POC2-RSP] Evidence: {0}' -f $path)
Write-Host ('[POC2-RSP] Expected fingerprint: {0}' -f $expectedFingerprint)
Write-Host ('[POC2-RSP] Actual fingerprint  : {0}' -f $archiveInventory.fingerprint)

foreach ($item in $responseState) {
	Write-Host ('[POC2-RSP] Response {0} after run: {1}' -f $item.key, $(if ($item.workingAfter.exists) { 'preserved' } else { 'deleted' }))
}

if ($process.looksLikeCrash) {
	throw ('LhaForge appears to have crashed: {0}' -f $process.exitCodeHex)
}
if (-not $passed) {
	throw ('Response File case failed: {0}. Stop and review before continuing.' -f $CaseId)
}

Write-Host ('[POC2-RSP] {0}/response/{1} passed.' -f $Target, $CaseId)
