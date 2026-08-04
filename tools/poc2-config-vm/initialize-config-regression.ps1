#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot
$evidenceRoot = Join-Path $kitRoot 'evidence'
$statePath = Join-Path $evidenceRoot 'state-before.json'
$commonScript = Join-Path $PSScriptRoot 'common.ps1'
. $commonScript

function Test-IsElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

foreach ($name in @('original', 'modern')) {
    $exe = Join-Path $kitRoot ($name + '\LhaForge.exe')
    $iniTemplate = Join-Path $kitRoot ($name + '\LhaForge.ini.template')
    $caldixTemplate = Join-Path $kitRoot ($name + '\LFCaldix.ini.template')
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw ('Missing binary: {0}' -f $exe) }
    if (-not (Test-Path -LiteralPath $iniTemplate -PathType Leaf)) { throw ('Missing template: {0}' -f $iniTemplate) }
    if (-not (Test-Path -LiteralPath $caldixTemplate -PathType Leaf)) { throw ('Missing template: {0}' -f $caldixTemplate) }
}

$running = @(Get-Process -Name 'LhaForge' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw 'Close every LhaForge process before initialization.'
}

if (Test-IsElevated) {
    throw 'Run this configuration regression from a normal non-elevated PowerShell window.'
}

$driveRoot = [System.IO.Path]::GetPathRoot((Get-Item -LiteralPath $kitRoot).FullName)
$driveInfo = New-Object System.IO.DriveInfo($driveRoot)
if ($driveInfo.DriveType -ne [System.IO.DriveType]::Fixed) {
    throw ('Copy and extract the VM kit to a fixed local disk before running it. Current drive type: {0}' -f $driveInfo.DriveType)
}

$indicators = @(Get-LhaForgeIntegrationIndicators)
if ($indicators.Count -gt 0) {
    Write-Host '[NG] Existing LhaForge Windows integration was detected:'
    foreach ($indicator in $indicators) { Write-Host ('  {0}' -f $indicator) }
    throw 'Use a clean VM snapshot with no LhaForge association or shell extension registered.'
}

if (Test-Path -LiteralPath $evidenceRoot) {
    if (-not $Force) {
        throw ('Evidence already exists. Review it or rerun with -Force: {0}' -f $evidenceRoot)
    }
    Remove-Item -LiteralPath $evidenceRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null

foreach ($name in @('original', 'modern')) {
    $targetRoot = Join-Path $kitRoot $name
    Copy-Item -LiteralPath (Join-Path $targetRoot 'LhaForge.ini.template') -Destination (Join-Path $targetRoot 'LhaForge.ini') -Force
    Copy-Item -LiteralPath (Join-Path $targetRoot 'LFCaldix.ini.template') -Destination (Join-Path $targetRoot 'LFCaldix.ini') -Force
}

$state = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    kitRoot = (Get-Item -LiteralPath $kitRoot).FullName
    externalState = Get-ExternalState
}
$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host ''
Write-Host '[POC2-CONFIG] VM initialization passed.'
Write-Host ('[POC2-CONFIG] State snapshot: {0}' -f $statePath)
Write-Host ''
Write-Host '[POC2-CONFIG] Test Original first:'
Write-Host ('  {0}' -f (Join-Path $kitRoot 'original\Launch.cmd'))
Write-Host '[POC2-CONFIG] Follow CHECKLIST.md exactly and stop if a UAC prompt or assistant error appears.'
