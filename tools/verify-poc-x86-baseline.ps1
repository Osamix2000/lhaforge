#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build-poc-x86.ps1'
$reportRoot = Join-Path $repoRoot '.baseline'
$reportPath = Join-Path $reportRoot 'poc1-x86-baseline.json'

function Get-PeMachine {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        try {
            if ($reader.ReadUInt16() -ne 0x5A4D) {
                throw ('Not a PE image (missing MZ): {0}' -f $Path)
            }

            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
                throw ('Invalid PE header offset: {0}' -f $Path)
            }

            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw ('Not a PE image (missing PE signature): {0}' -f $Path)
            }

            return $reader.ReadUInt16()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-BinaryEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$Configuration
    )

    $path = Join-Path $repoRoot ('{0}\LhaForge.exe' -f $Configuration)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Build output was not found: {0}' -f $path)
    }

    $machine = Get-PeMachine -Path $path
    if ($machine -ne 0x014C) {
        throw ('Expected Win32/x86 PE machine 0x014C but got 0x{0:X4}: {1}' -f $machine, $path)
    }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $file = Get-Item -LiteralPath $path
    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)

    [pscustomobject]@{
        configuration = $Configuration
        path = $path
        peMachine = '0x014c'
        architecture = 'x86'
        sizeBytes = $file.Length
        sha256 = $hash
        fileVersion = [string]$version.FileVersion
        productVersion = [string]$version.ProductVersion
    }
}

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw ('Build helper was not found: {0}' -f $buildScript)
}

foreach ($configuration in @('Debug', 'Release')) {
    Write-Host ''
    Write-Host ('[BASELINE] Building {0}|Win32...' -f $configuration)

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $buildScript,
        '-Configuration', $configuration
    )
    if ($Rebuild) {
        $args += '-Rebuild'
    }

    & powershell.exe @args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$debugEvidence = Get-BinaryEvidence -Configuration 'Debug'
$releaseEvidence = Get-BinaryEvidence -Configuration 'Release'

if (-not (Test-Path -LiteralPath $reportRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $reportRoot | Out-Null
}

$report = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'PoC 1 modern x86 build evidence'
    binaries = @($debugEvidence, $releaseEvidence)
}

$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host '[BASELINE] PoC 1 x86 build evidence'
foreach ($item in @($debugEvidence, $releaseEvidence)) {
    Write-Host ('[OK] {0}|Win32 PE machine: {1} ({2})' -f $item.configuration, $item.peMachine, $item.architecture)
    Write-Host ('     Size: {0} bytes' -f $item.sizeBytes)
    Write-Host ('     SHA-256: {0}' -f $item.sha256)
    if (-not [string]::IsNullOrWhiteSpace($item.fileVersion)) {
        Write-Host ('     File version: {0}' -f $item.fileVersion)
    }
    if (-not [string]::IsNullOrWhiteSpace($item.productVersion)) {
        Write-Host ('     Product version: {0}' -f $item.productVersion)
    }
}

Write-Host ''
Write-Host ('[BASELINE] Local report: {0}' -f $reportPath)
Write-Host '[BASELINE] Manual startup / behavior checks remain separate from this script.'
Write-Host '[BASELINE] Build and PE architecture verification passed.'
exit 0
