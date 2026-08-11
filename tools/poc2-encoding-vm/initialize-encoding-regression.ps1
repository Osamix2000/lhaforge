#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-KitRoot
$manifestPath = Join-Path $kitRoot 'manifest.json'
$evidenceRoot = Join-Path $kitRoot 'evidence'
$fixtureRoot = Join-Path $kitRoot 'fixture'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw ('manifest.json was not found: {0}' -f $manifestPath)
}

if (Test-IsElevated) {
    throw 'Run the PoC 2-C1 VM kit from a non-elevated PowerShell session.'
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

    if ($exe.sha256 -cne [string]$manifest.$target.exe.sha256) {
        throw ('{0} LhaForge.exe hash mismatch.' -f $target)
    }
    if ($dll.sha256 -cne [string]$manifest.$target.dll.sha256) {
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
if ($originalDll.sha256 -cne [string]$manifest.fixedBackend.sha256) {
    throw '7-ZIP32.DLL does not match the PoC 2-C fixed backend hash.'
}

$fixture = New-Poc2C1Fixture -Root $fixtureRoot

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
    fixture = $fixture
    external = Get-ExternalState
    tempZip = @(Get-TempZipState)
}
Write-JsonUtf8NoBom -Value $state -Path (Join-Path $evidenceRoot 'state-before.json') -Depth 20

Write-Host '[POC2-ENC] PoC 2-C1 VM initialization passed.'
Write-Host ('[POC2-ENC] Kit root       : {0}' -f $kitRoot)
Write-Host ('[POC2-ENC] DLL SHA-256    : {0}' -f $originalDll.sha256)
Write-Host ('[POC2-ENC] Reference ZIP  : {0}' -f $fixture.referenceZip.sha256)
Write-Host ('[POC2-ENC] Fixture files  : {0}' -f $fixture.inputInventory.files.Count)
Write-Host ('[POC2-ENC] Fixture dirs   : {0}' -f $fixture.inputInventory.directories.Count)
Write-Host ''
Write-Host '[POC2-ENC] Cases:'
foreach ($case in $fixture.cases) {
    Write-Host ('  {0,-14} {1}' -f $case.id, (($case.token.codePoints) -join ' '))
}
Write-Host ''
Write-Host '[POC2-ENC] Next: run the Original list case from CHECKLIST.md.'
