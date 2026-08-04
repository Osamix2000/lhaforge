#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OriginalExe,

    [ValidateSet('Debug', 'Release')]
    [string]$ModernConfiguration = 'Release',

    [switch]$Rebuild,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build-poc-x86.ps1'
$commonScript = Join-Path $PSScriptRoot 'poc2-config-vm\common.ps1'
$vmScriptRoot = Join-Path $PSScriptRoot 'poc2-config-vm'
$checklistSource = Join-Path $vmScriptRoot 'CHECKLIST.md'
$outputRoot = Join-Path $repoRoot '.baseline\poc2-config'
$kitRoot = Join-Path $outputRoot 'vm-kit'
$zipPath = Join-Path $outputRoot 'poc2-config-vm-kit.zip'

. $commonScript

function Write-Utf16File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Stage-Target {
    param(
        [Parameter(Mandatory = $true)][string]$SourceExe,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $SourceExe -Destination (Join-Path $Destination 'LhaForge.exe') -Force

    $initialConfig = @'
[Update]
SilentUpdate=0
AskUpdate=0
Interval=9999

[LogView]
LogViewEvent=0

[Output]
WarnNetwork=0
WarnRemovable=0
OnDirNotFound=2

[Compress]
OpenFolder=1

[FileListWindow]
ExitWithEscape=0
'@

    $caldixConfig = @'
[conf]
dll=

[Update]
LastTime=0
'@

    Write-Utf16File -Path (Join-Path $Destination 'LhaForge.ini.template') -Content $initialConfig
    Write-Utf16File -Path (Join-Path $Destination 'LFCaldix.ini.template') -Content $caldixConfig
    Copy-Item -LiteralPath (Join-Path $Destination 'LhaForge.ini.template') -Destination (Join-Path $Destination 'LhaForge.ini') -Force
    Copy-Item -LiteralPath (Join-Path $Destination 'LFCaldix.ini.template') -Destination (Join-Path $Destination 'LFCaldix.ini') -Force
    New-Item -ItemType Directory -Path (Join-Path $Destination 'dll') -Force | Out-Null

    $launch = @'
@echo off
cd /d "%~dp0"
"%~dp0LhaForge.exe" "/cfg:%~dp0LhaForge.ini"
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $Destination 'Launch.cmd'),
        $launch,
        [System.Text.Encoding]::ASCII
    )

    return Get-FileEvidence -Path (Join-Path $Destination 'LhaForge.exe')
}

$OriginalExe = [System.IO.Path]::GetFullPath($OriginalExe)
if (-not (Test-Path -LiteralPath $OriginalExe -PathType Leaf)) {
    throw ('Original LhaForge.exe was not found: {0}' -f $OriginalExe)
}
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw ('Build helper was not found: {0}' -f $buildScript)
}
if (-not (Test-Path -LiteralPath $commonScript -PathType Leaf)) {
    throw ('VM common helper was not found: {0}' -f $commonScript)
}
if (-not (Test-Path -LiteralPath $checklistSource -PathType Leaf)) {
    throw ('Checklist was not found: {0}' -f $checklistSource)
}

Write-Host ('[POC2-CONFIG] Building modern {0}|Win32...' -f $ModernConfiguration)
$buildArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $buildScript,
    '-Configuration', $ModernConfiguration
)
if ($Rebuild) { $buildArgs += '-Rebuild' }

& powershell.exe @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$modernExe = Join-Path $repoRoot ('{0}\LhaForge.exe' -f $ModernConfiguration)
if (-not (Test-Path -LiteralPath $modernExe -PathType Leaf)) {
    throw ('Modern build output was not found: {0}' -f $modernExe)
}

if (Test-Path -LiteralPath $outputRoot) {
    if (-not $Force) {
        throw ('PoC 2 config output already exists. Review it or rerun with -Force: {0}' -f $outputRoot)
    }
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $kitRoot -Force | Out-Null

$originalEvidence = Stage-Target -SourceExe $OriginalExe -Destination (Join-Path $kitRoot 'original')
$modernEvidence = Stage-Target -SourceExe $modernExe -Destination (Join-Path $kitRoot 'modern')

if ($originalEvidence.peMachine -ne '0x014c') {
    throw ('Original binary is not Win32/x86: {0}' -f $originalEvidence.path)
}
if ($modernEvidence.peMachine -ne '0x014c') {
    throw ('Modern binary is not Win32/x86: {0}' -f $modernEvidence.path)
}

$kitScriptRoot = Join-Path $kitRoot 'scripts'
New-Item -ItemType Directory -Path $kitScriptRoot -Force | Out-Null
foreach ($name in @('common.ps1', 'initialize-config-regression.ps1', 'capture-config-result.ps1', 'compare-config-results.ps1')) {
    Copy-Item -LiteralPath (Join-Path $vmScriptRoot $name) -Destination (Join-Path $kitScriptRoot $name) -Force
}
Copy-Item -LiteralPath $checklistSource -Destination (Join-Path $kitRoot 'CHECKLIST.md') -Force

$manifest = [ordered]@{
    schemaVersion = 1
    preparedUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'PoC 2-A config save and reload regression VM kit'
    original = $originalEvidence
    modern = $modernEvidence
    expectedChanges = @(
        [ordered]@{ section = 'LogView'; key = 'LogViewEvent'; value = '1' },
        [ordered]@{ section = 'Output'; key = 'WarnNetwork'; value = '1' },
        [ordered]@{ section = 'Output'; key = 'OnDirNotFound'; value = '1' },
        [ordered]@{ section = 'Compress'; key = 'OpenFolder'; value = '0' },
        [ordered]@{ section = 'FileListWindow'; key = 'ExitWithEscape'; value = '1' },
        [ordered]@{ section = 'Update'; key = 'AskUpdate'; value = '0' }
    )
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $kitRoot 'manifest.json') -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $kitRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ''
Write-Host '[POC2-CONFIG] VM kit prepared.'
Write-Host ('[POC2-CONFIG] Directory: {0}' -f $kitRoot)
Write-Host ('[POC2-CONFIG] ZIP      : {0}' -f $zipPath)
Write-Host ''
Write-Host '[POC2-CONFIG] Original evidence'
Write-Host ('  Version: {0}' -f $originalEvidence.fileVersion)
Write-Host ('  SHA-256: {0}' -f $originalEvidence.sha256)
Write-Host '[POC2-CONFIG] Modern evidence'
Write-Host ('  Version: {0}' -f $modernEvidence.fileVersion)
Write-Host ('  SHA-256: {0}' -f $modernEvidence.sha256)
Write-Host ''
Write-Host '[POC2-CONFIG] Copy the ZIP to the Windows VM local disk, extract it, and read CHECKLIST.md.'
