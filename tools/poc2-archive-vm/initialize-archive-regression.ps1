#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-KitRoot
$manifestPath = Join-Path $kitRoot 'manifest.json'
$evidenceRoot = Join-Path $kitRoot 'evidence'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw ('manifest.json was not found: {0}' -f $manifestPath)
}

if (Test-IsElevated) {
    throw 'Run the PoC 2-B VM kit from a non-elevated PowerShell session.'
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

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

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

    $expectedExeHash = [string]$manifest.$target.exe.sha256
    $expectedDllHash = [string]$manifest.$target.dll.sha256
    if ($exe.sha256 -cne $expectedExeHash) {
        throw ('{0} LhaForge.exe hash mismatch.' -f $target)
    }
    if ($dll.sha256 -cne $expectedDllHash) {
        throw ('{0} 7-ZIP32.DLL hash mismatch.' -f $target)
    }

    Copy-Item -LiteralPath (Join-Path $targetRoot 'LhaForge.ini.template') -Destination (Join-Path $targetRoot 'LhaForge.ini') -Force
    Copy-Item -LiteralPath (Join-Path $targetRoot 'LFCaldix.ini.template') -Destination (Join-Path $targetRoot 'LFCaldix.ini') -Force

    $results = Join-Path $targetRoot 'results'
    if (Test-Path -LiteralPath $results) {
        Remove-Item -LiteralPath $results -Recurse -Force
    }
    New-Item -ItemType Directory -Path $results -Force | Out-Null
}

$originalDll = Get-FileEvidence -Path (Join-Path $kitRoot 'original\7-ZIP32.DLL')
$modernDll = Get-FileEvidence -Path (Join-Path $kitRoot 'modern\7-ZIP32.DLL')
if ($originalDll.sha256 -cne $modernDll.sha256) {
    throw 'Original and Modern are not using the same 7-ZIP32.DLL bytes.'
}

$fixtureRoot = Join-Path $kitRoot 'fixture\input'
$referenceZip = Join-Path $kitRoot 'fixture\reference.zip'
$fixtureInventory = Get-DirectoryInventory -Path $fixtureRoot
$referenceEvidence = Get-FileHashEvidence -Path $referenceZip

if ($fixtureInventory.fingerprint -cne [string]$manifest.fixture.input.fingerprint) {
    throw 'Fixture directory fingerprint mismatch.'
}
if ($referenceEvidence.sha256 -cne [string]$manifest.fixture.referenceZip.sha256) {
    throw 'Reference ZIP hash mismatch.'
}

if (Test-Path -LiteralPath $evidenceRoot) {
    Remove-Item -LiteralPath $evidenceRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

$state = [ordered]@{
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    kitRoot = $kitRoot
    external = Get-ExternalState
    tempZip = @(Get-TempZipState)
    fixtureFingerprint = $fixtureInventory.fingerprint
    referenceZipSha256 = $referenceEvidence.sha256
    sevenZipDllSha256 = $originalDll.sha256
}
$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'state-before.json') -Encoding UTF8

Write-Host '[POC2-ARCHIVE] VM initialization passed.'
Write-Host ('[POC2-ARCHIVE] Kit root      : {0}' -f $kitRoot)
Write-Host ('[POC2-ARCHIVE] DLL SHA-256   : {0}' -f $originalDll.sha256)
Write-Host ('[POC2-ARCHIVE] Reference ZIP : {0}' -f $referenceEvidence.sha256)
Write-Host ('[POC2-ARCHIVE] Fixture files : {0}' -f $fixtureInventory.files.Count)
Write-Host ''
Write-Host '[POC2-ARCHIVE] Next: run the Original List operation from CHECKLIST.md.'
