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
$baselineRoot = Join-Path $repoRoot '.baseline'
$root = Join-Path $baselineRoot 'poc2-ui'
$originalRoot = Join-Path $root 'original'
$modernRoot = Join-Path $root 'modern'
$statePath = Join-Path $root 'external-state-before.json'
$checklistPath = Join-Path $root 'CHECKLIST.md'

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )

    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        try {
            if ($reader.ReadUInt16() -ne 0x5A4D) {
                throw ('Not a PE image: {0}' -f $Path)
            }

            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
                throw ('Invalid PE header offset: {0}' -f $Path)
            }

            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw ('Missing PE signature: {0}' -f $Path)
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

function Get-FileEvidence {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('File was not found: {0}' -f $Path)
    }

    $file = Get-Item -LiteralPath $Path
    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $machine = Get-PeMachine -Path $Path

    [pscustomobject]@{
        path = $file.FullName
        sizeBytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        peMachine = ('0x{0:x4}' -f $machine)
        architecture = if ($machine -eq 0x014C) { 'x86' } else { 'other' }
        fileVersion = [string]$version.FileVersion
        productVersion = [string]$version.ProductVersion
    }
}

function Get-PathState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            name = $Name
            path = $Path
            exists = $false
            kind = $null
            sizeBytes = $null
            sha256 = $null
            lastWriteUtc = $null
        }
    }

    $item = Get-Item -LiteralPath $Path
    $isFile = -not $item.PSIsContainer

    [pscustomobject]@{
        name = $Name
        path = $item.FullName
        exists = $true
        kind = if ($isFile) { 'file' } else { 'directory' }
        sizeBytes = if ($isFile) { $item.Length } else { $null }
        sha256 = if ($isFile) { (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
    }
}

function Write-Utf16File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Stage-LhaForge {
    param(
        [Parameter(Mandatory = $true)][string]$SourceExe,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $exe = Join-Path $Destination 'LhaForge.exe'
    Copy-Item -LiteralPath $SourceExe -Destination $exe -Force

    $config = @'
[Update]
SilentUpdate=0
AskUpdate=0
Interval=21
'@

    $caldix = @'
[conf]
dll=

[Update]
LastTime=0
'@

    Write-Utf16File -Path (Join-Path $Destination 'LhaForge.ini') -Content $config
    Write-Utf16File -Path (Join-Path $Destination 'LFCaldix.ini') -Content $caldix

    $launch = @'
@echo off
start "" "%~dp0LhaForge.exe" "/cfg:%~dp0LhaForge.ini"
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $Destination 'Launch.cmd'),
        $launch.Replace("`n", "`r`n"),
        [System.Text.Encoding]::ASCII
    )

    New-Item -ItemType Directory -Path (Join-Path $Destination 'dll') -Force | Out-Null

    return Get-FileEvidence -Path $exe
}

$OriginalExe = [System.IO.Path]::GetFullPath($OriginalExe)
if (-not (Test-Path -LiteralPath $OriginalExe -PathType Leaf)) {
    throw ('Original LhaForge.exe was not found: {0}' -f $OriginalExe)
}

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw ('Build helper was not found: {0}' -f $buildScript)
}

$buildArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $buildScript,
    '-Configuration', $ModernConfiguration
)
if ($Rebuild) {
    $buildArgs += '-Rebuild'
}

Write-Host ('[POC2] Building modern {0}|Win32...' -f $ModernConfiguration)
& powershell.exe @buildArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$modernExe = Join-Path $repoRoot ('{0}\LhaForge.exe' -f $ModernConfiguration)
if (-not (Test-Path -LiteralPath $modernExe -PathType Leaf)) {
    throw ('Modern build output was not found: {0}' -f $modernExe)
}

if (Test-Path -LiteralPath $root) {
    if (-not $Force) {
        throw ('PoC 2 UI sandbox already exists. Review it or rerun with -Force: {0}' -f $root)
    }
    Remove-Item -LiteralPath $root -Recurse -Force
}

New-Item -ItemType Directory -Path $root -Force | Out-Null

$appDataRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'LhaForge'
$programDataRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'LhaForge'

$externalPaths = @(
    [pscustomobject]@{ name = 'AppData LhaForge directory'; path = $appDataRoot },
    [pscustomobject]@{ name = 'AppData LhaForge.ini'; path = (Join-Path $appDataRoot 'LhaForge.ini') },
    [pscustomobject]@{ name = 'ProgramData LhaForge directory'; path = $programDataRoot },
    [pscustomobject]@{ name = 'ProgramData LhaForge.ini'; path = (Join-Path $programDataRoot 'LhaForge.ini') },
    [pscustomobject]@{ name = 'ProgramData LFCaldix.ini'; path = (Join-Path $programDataRoot 'LFCaldix.ini') }
)

$before = @()
foreach ($entry in $externalPaths) {
    $before += Get-PathState -Name $entry.name -Path $entry.path
}

$originalEvidence = Stage-LhaForge -SourceExe $OriginalExe -Destination $originalRoot
$modernEvidence = Stage-LhaForge -SourceExe $modernExe -Destination $modernRoot

if ($originalEvidence.peMachine -ne '0x014c') {
    throw ('Original binary is not Win32/x86: {0}' -f $originalEvidence.path)
}
if ($modernEvidence.peMachine -ne '0x014c') {
    throw ('Modern binary is not Win32/x86: {0}' -f $modernEvidence.path)
}

$state = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'PoC 2-A external configuration isolation snapshot'
    original = $originalEvidence
    modern = $modernEvidence
    externalPaths = $before
}

$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8

$checklist = @'
# PoC 2-A UI regression checklist

This checklist is local test evidence and is not committed.

Rules for the first pass:

- Run only the staged copies under this directory.
- Do not run the installed/original executable in-place.
- Do not use association, shell-extension, or DLL update actions.
- Do not press OK in the first pass. Close the configuration dialog with Cancel.
- Compare Original first, then Modern under the same sandbox conditions.

## Original v1.6.7

- [ ] Launch.cmd starts without an immediate crash.
- [ ] Configuration dialog appears.
- [ ] Window title / version presentation looks expected.
- [ ] General page opens.
- [ ] Compression-related pages open.
- [ ] Extraction-related pages open.
- [ ] DLL / update-related pages can be viewed without starting an update.
- [ ] Controls are readable and not obviously clipped.
- [ ] Cancel closes cleanly.

Notes:

```text

```

## Modern x86

- [ ] Launch.cmd starts without an immediate crash.
- [ ] Configuration dialog appears.
- [ ] Window title / version presentation matches the Original unless documented.
- [ ] General page opens.
- [ ] Compression-related pages open.
- [ ] Extraction-related pages open.
- [ ] DLL / update-related pages can be viewed without starting an update.
- [ ] Controls are readable and not obviously clipped.
- [ ] Cancel closes cleanly.

Notes:

```text

```

## Comparison

Classification:

- MATCH
- EXPECTED_DIFFERENCE
- REGRESSION
- SECURITY_CHANGE_REQUIRED
- UNKNOWN

Result:

```text
Overall:
Differences:
Classification:
```
'@

[System.IO.File]::WriteAllText($checklistPath, $checklist.Replace("`n", "`r`n"), [System.Text.Encoding]::UTF8)

Write-Host ''
Write-Host '[POC2] Sandbox prepared.'
Write-Host ('[POC2] Original: {0}' -f $originalRoot)
Write-Host ('[POC2] Modern  : {0}' -f $modernRoot)
Write-Host ('[POC2] Checklist: {0}' -f $checklistPath)
Write-Host ''
Write-Host '[POC2] Original evidence'
Write-Host ('  Version: {0}' -f $originalEvidence.fileVersion)
Write-Host ('  SHA-256: {0}' -f $originalEvidence.sha256)
Write-Host '[POC2] Modern evidence'
Write-Host ('  Version: {0}' -f $modernEvidence.fileVersion)
Write-Host ('  SHA-256: {0}' -f $modernEvidence.sha256)
Write-Host ''
Write-Host '[POC2] Start with:'
Write-Host ('  {0}' -f (Join-Path $originalRoot 'Launch.cmd'))
Write-Host ('  {0}' -f (Join-Path $modernRoot 'Launch.cmd'))
Write-Host ''
Write-Host '[POC2] After both Cancel-only UI checks, run:'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-poc2-ui-isolation.ps1'
