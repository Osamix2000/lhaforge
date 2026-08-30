#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'c3-common.ps1')

$kitRoot = Get-KitRoot
$manifestPath = Join-Path $kitRoot 'manifest.json'
$evidenceRoot = Join-Path $kitRoot 'evidence-c3'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw ('manifest.json was not found: {0}' -f $manifestPath)
}
if (Test-IsElevated) {
    throw 'Run the PoC 2-C3 VM kit from a non-elevated Windows PowerShell session.'
}

$driveRoot = [System.IO.Path]::GetPathRoot($kitRoot)
$drive = New-Object System.IO.DriveInfo($driveRoot)
if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
    throw ('VM kit must be on a local fixed disk. Current drive type: {0}' -f $drive.DriveType)
}

$running = @(Get-Process -Name LhaForge -ErrorAction SilentlyContinue)
if ($running.Count -ne 0) {
    throw 'Close all LhaForge processes before initialization.'
}

$manifest = Read-JsonUtf8 -Path $manifestPath

foreach ($target in @('original', 'modern')) {
    $targetRoot = Join-Path $kitRoot $target
    $exePath = Join-Path $targetRoot 'LhaForge.exe'
    $dllPath = Join-Path $targetRoot '7-ZIP32.DLL'

    $exe = Get-FileEvidence -Path $exePath
    $dll = Get-FileEvidence -Path $dllPath

    if ($exe.peMachine -ne '0x014c') { throw ('{0} LhaForge.exe is not x86.' -f $target) }
    if ($dll.peMachine -ne '0x014c') { throw ('{0} 7-ZIP32.DLL is not x86.' -f $target) }

    if ($exe.sha256 -cne [string]$manifest.$target.exe.sha256) {
        throw ('{0} LhaForge.exe hash mismatch.' -f $target)
    }
    if ($dll.sha256 -cne [string]$manifest.$target.dll.sha256) {
        throw ('{0} 7-ZIP32.DLL hash mismatch.' -f $target)
    }

    Copy-Item -LiteralPath (Join-Path $targetRoot 'LhaForge.ini.template') -Destination (Join-Path $targetRoot 'LhaForge.ini') -Force
    Copy-Item -LiteralPath (Join-Path $targetRoot 'LFCaldix.ini.template') -Destination (Join-Path $targetRoot 'LFCaldix.ini') -Force

    foreach ($sub in @('c3-run-records', 'c3-extract')) {
        $p = Join-Path (Join-Path $targetRoot 'results') $sub
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
}

$originalDll = Get-FileEvidence -Path (Join-Path $kitRoot 'original\7-ZIP32.DLL')
$modernDll = Get-FileEvidence -Path (Join-Path $kitRoot 'modern\7-ZIP32.DLL')
if ($originalDll.sha256 -cne $modernDll.sha256) {
    throw 'Original and Modern are not using the same 7-ZIP32.DLL bytes.'
}
if ($originalDll.sha256 -cne [string]$manifest.fixedBackend.sha256) {
    throw '7-ZIP32.DLL does not match the PoC 2-C fixed backend hash.'
}

$fixtureManifest = Get-C3FixtureManifest
if (@($fixtureManifest.cases).Count -ne 15) {
    throw ('Expected 15 C3 fixture cases, found {0}.' -f @($fixtureManifest.cases).Count)
}

$fixtureEvidence = @()
foreach ($case in Get-Poc2C3FrozenCases) {
    $actual = Assert-C3FixtureIdentity -CaseId $case.id
    $fixtureEvidence += $actual
}

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
    fixtureManifestSha256 = (Get-FileHash -LiteralPath (Join-Path (Get-C3FixtureRoot) 'fixture-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    fixtures = @($fixtureEvidence)
    external = Get-ExternalState
    tempZip = @(Get-TempZipState)
}
Write-JsonUtf8NoBom -Value $state -Path (Join-Path $evidenceRoot 'state-before-c3.json') -Depth 20

Write-Host '[POC2-C3] VM initialization passed.'
Write-Host ('[POC2-C3] Kit root    : {0}' -f $kitRoot)
Write-Host ('[POC2-C3] Repo HEAD   : {0}' -f $manifest.repoHead)
Write-Host ('[POC2-C3] DLL SHA-256 : {0}' -f $originalDll.sha256)
Write-Host '[POC2-C3] Fixtures    : 15 / 15 identity checks passed.'
Write-Host ''
Write-Host '[POC2-C3] Next: run-c3-target.ps1 -Target original'
