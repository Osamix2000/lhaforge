#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'response-common.ps1')
. (Join-Path $PSScriptRoot 'abnormal-response-common.ps1')

$kitRoot = Get-KitRoot
$manifestPath = Join-Path $kitRoot 'manifest.json'
$evidenceRoot = Join-Path $kitRoot 'evidence-response-abnormal'
$fixtureRoot = Join-Path $kitRoot 'fixture-response-abnormal'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
	throw ('manifest.json was not found: {0}' -f $manifestPath)
}

if (Test-IsElevated) {
	throw 'Run the PoC 2-C2 abnormal VM kit from a non-elevated Windows PowerShell session.'
}

$driveRoot = [System.IO.Path]::GetPathRoot($kitRoot)
$drive = New-Object System.IO.DriveInfo($driveRoot)
if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
	throw ('VM kit must be on a local fixed disk. Current drive type: {0}' -f $drive.DriveType)
}

Assert-Poc2C2AbnormalAsciiPath -Path $kitRoot

$running = @(Get-Process -Name LhaForge -ErrorAction SilentlyContinue)
if ($running.Count -ne 0) {
	throw 'Close all LhaForge processes before C2 abnormal initialization.'
}

$runtime = Get-Poc2C2RuntimeEvidence
$runtimePsVersion = [version]$runtime.powerShellVersion
if (
	[string]$runtime.psEdition -cne 'Desktop' -or
	$runtimePsVersion.Major -ne 5 -or
	$runtimePsVersion.Minor -ne 1
) {
	throw ('PoC 2-C2 abnormal regression requires Windows PowerShell 5.1 exactly. Current runtime: PowerShell {0}, PSEdition {1}.' -f $runtime.powerShellVersion, $runtime.psEdition)
}
if ([int]$runtime.defaultEncodingCodePage -ne 932) {
	throw ('PoC 2-C2 abnormal CP932 baseline requires Windows ANSI code page 932. Current code page: {0}. Do not change system settings automatically; stop and review the VM environment.' -f $runtime.defaultEncodingCodePage)
}

Assert-Poc2C2EncodingByteGenerator
Assert-Poc2C2AbnormalByteGenerator

$manifest = Read-JsonUtf8 -Path $manifestPath

foreach ($target in @('original', 'modern')) {
	$targetRoot = Join-Path $kitRoot $target
	$exePath = Join-Path $targetRoot 'LhaForge.exe'
	$dllPath = Join-Path $targetRoot '7-ZIP32.DLL'

	$exe = Get-FileEvidence -Path $exePath
	$dll = Get-FileEvidence -Path $dllPath

	if ($exe.peMachine -ne '0x014c') {
		throw ('{0} LhaForge.exe is not x86.' -f $target)
	}
	if ($dll.peMachine -ne '0x014c') {
		throw ('{0} 7-ZIP32.DLL is not x86.' -f $target)
	}
	if ($exe.sha256 -cne [string]$manifest.$target.exe.sha256) {
		throw ('{0} LhaForge.exe hash mismatch.' -f $target)
	}
	if ($dll.sha256 -cne [string]$manifest.$target.dll.sha256) {
		throw ('{0} 7-ZIP32.DLL hash mismatch.' -f $target)
	}

	Copy-Item -LiteralPath (Join-Path $targetRoot 'LhaForge.ini.template') -Destination (Join-Path $targetRoot 'LhaForge.ini') -Force
	Copy-Item -LiteralPath (Join-Path $targetRoot 'LFCaldix.ini.template') -Destination (Join-Path $targetRoot 'LFCaldix.ini') -Force

	$resultRoot = Join-Path $targetRoot 'response-abnormal-results'
	if (Test-Path -LiteralPath $resultRoot) {
		Remove-Item -LiteralPath $resultRoot -Recurse -Force
	}
	New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
}

$targets = [ordered]@{
	original = [ordered]@{
		exe = Get-FileEvidence -Path (Join-Path $kitRoot 'original\LhaForge.exe')
		dll = Get-FileEvidence -Path (Join-Path $kitRoot 'original\7-ZIP32.DLL')
	}
	modern = [ordered]@{
		exe = Get-FileEvidence -Path (Join-Path $kitRoot 'modern\LhaForge.exe')
		dll = Get-FileEvidence -Path (Join-Path $kitRoot 'modern\7-ZIP32.DLL')
	}
}

$originalDll = $targets.original.dll
$modernDll = $targets.modern.dll
if ($originalDll.sha256 -cne $modernDll.sha256) {
	throw 'Original and Modern are not using the same 7-ZIP32.DLL bytes.'
}
if ($originalDll.sha256 -cne [string]$manifest.fixedBackend.sha256) {
	throw '7-ZIP32.DLL does not match the PoC 2-C fixed backend hash.'
}

$fixture = New-Poc2C2AbnormalFixture -Root $fixtureRoot

if (Test-Path -LiteralPath $evidenceRoot) {
	Remove-Item -LiteralPath $evidenceRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

$state = [ordered]@{
	schemaVersion = 1
	capturedUtc = [DateTime]::UtcNow.ToString('o')
	kitRoot = $kitRoot
	repoHead = [string]$manifest.repoHead
	sevenZipDllSha256 = $originalDll.sha256
	runtime = $runtime
	targets = $targets
	fixture = $fixture
	external = Get-ExternalState
	tempZip = @(Get-TempZipState)
	normalEvidenceDirectoriesTouched = $false
}
Write-JsonUtf8NoBom -Value $state -Path (Join-Path $evidenceRoot 'state-before.json') -Depth 28

Write-Host '[POC2-RSP-ABN] PoC 2-C2 abnormal VM initialization passed.'
Write-Host ('[POC2-RSP-ABN] Kit root        : {0}' -f $kitRoot)
Write-Host ('[POC2-RSP-ABN] DLL SHA-256     : {0}' -f $originalDll.sha256)
Write-Host ('[POC2-RSP-ABN] ANSI code page  : {0}' -f $runtime.defaultEncodingCodePage)
Write-Host ('[POC2-RSP-ABN] Culture         : {0}' -f $runtime.currentCulture)
Write-Host ('[POC2-RSP-ABN] Abnormal cases  : {0}' -f $fixture.cases.Count)
Write-Host ''
Write-Host '[POC2-RSP-ABN] Run order:'
foreach ($case in Get-Poc2C2AbnormalCases) {
	$risk = if ([bool]$case.expectation.highRisk) { ' HIGH-RISK / RUN LAST' } else { '' }
	Write-Host ('  {0}{1}' -f $case.id, $risk)
}
Write-Host ''
Write-Host '[POC2-RSP-ABN] Normal C2 fixture/evidence directories were not initialized or removed.'
Write-Host '[POC2-RSP-ABN] Next: follow RESPONSE-ABNORMAL-CHECKLIST.md and run Original one case at a time.'
