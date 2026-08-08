#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OriginalExe,

    [Parameter(Mandatory = $true)]
    [string]$SevenZipDll,

    [ValidateSet('Debug', 'Release')]
    [string]$ModernConfiguration = 'Release',

    [switch]$Rebuild,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build-poc-x86.ps1'
$vmScriptRoot = Join-Path $PSScriptRoot 'poc2-archive-vm'
$outputRoot = Join-Path $repoRoot '.baseline\poc2-archive'
$kitRoot = Join-Path $outputRoot 'vm-kit'
$zipPath = Join-Path $outputRoot 'poc2-archive-vm-kit.zip'

. (Join-Path $vmScriptRoot 'common.ps1')

function Write-Utf16File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function New-Fixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    $inputRoot = Join-Path $Root 'input'
    New-Item -ItemType Directory -Path (Join-Path $inputRoot 'nested') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $inputRoot 'another') -Force | Out-Null

    [System.IO.File]::WriteAllText(
        (Join-Path $inputRoot 'root.txt'),
        "root line 1`r`nroot line 2`r`n",
        [System.Text.Encoding]::ASCII
    )
    [System.IO.File]::WriteAllBytes(
        (Join-Path $inputRoot 'empty.txt'),
        (New-Object byte[] 0)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $inputRoot 'nested\child.txt'),
        "child line`r`n",
        [System.Text.Encoding]::ASCII
    )
    $binary = New-Object byte[] 256
    for ($i = 0; $i -lt 256; $i++) { $binary[$i] = [byte]$i }
    [System.IO.File]::WriteAllBytes(
        (Join-Path $inputRoot 'nested\binary.bin'),
        $binary
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $inputRoot 'another\data.txt'),
        "alpha,beta,gamma`r`n",
        [System.Text.Encoding]::ASCII
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zipPathLocal = Join-Path $Root 'reference.zip'
    if (Test-Path -LiteralPath $zipPathLocal) {
        Remove-Item -LiteralPath $zipPathLocal -Force
    }

    $stream = [System.IO.File]::Open(
        $zipPathLocal,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $zip = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            $fixedTime = [DateTimeOffset]::Parse('2020-01-02T03:04:06+00:00')
            foreach ($dirName in @('another/', 'nested/')) {
                $entry = $zip.CreateEntry($dirName, [System.IO.Compression.CompressionLevel]::NoCompression)
                $entry.LastWriteTime = $fixedTime
            }

            $files = @(
                'another/data.txt',
                'empty.txt',
                'nested/binary.bin',
                'nested/child.txt',
                'root.txt'
            )
            foreach ($relative in $files) {
                $source = Join-Path $inputRoot ($relative.Replace('/', '\'))
                $entry = $zip.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTime
                $entryStream = $entry.Open()
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($source)
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally {
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    [System.IO.File]::WriteAllText(
        (Join-Path $Root 'EXPECTED_TREE.txt'),
        "another/data.txt`r`nempty.txt`r`nnested/binary.bin`r`nnested/child.txt`r`nroot.txt`r`n",
        [System.Text.Encoding]::ASCII
    )

    return [pscustomobject]@{
        input = Get-DirectoryInventory -Path $inputRoot
        referenceZip = Get-FileHashEvidence -Path $zipPathLocal
        referenceZipEntries = Get-ZipInventory -Path $zipPathLocal
    }
}

function Stage-Target {
    param(
        [Parameter(Mandatory = $true)][string]$SourceExe,
        [Parameter(Mandatory = $true)][string]$SourceDll,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $SourceExe -Destination (Join-Path $Destination 'LhaForge.exe') -Force
    Copy-Item -LiteralPath $SourceDll -Destination (Join-Path $Destination '7-ZIP32.DLL') -Force

    $config = @'
[Enable]
7ZIP=1

[Update]
SilentUpdate=0
AskUpdate=0
Interval=9999

[LogView]
LogViewEvent=0

[Output]
WarnNetwork=0
WarnRemovable=0
OnDirNotFound=1

[Compress]
OpenFolder=0
DeleteAfterCompress=0
IgnoreTopDirectory=0
SpecifyOutputFilename=0

[ZIP]
CompressType=0
CompressLevel=0
ForceUTF8=0
SpecifyDeflateMemorySize=0
DeflateMemorySize=32
SpecifyDeflatePassNumber=0
DeflatePassNumber=1
CryptoMode=0
SpecifySplitSize=0
SplitSize=10
SplitSizeUnit=0
'@

    $caldix = @'
[conf]
dll=

[Update]
LastTime=0
'@

    Write-Utf16File -Path (Join-Path $Destination 'LhaForge.ini.template') -Content $config
    Write-Utf16File -Path (Join-Path $Destination 'LFCaldix.ini.template') -Content $caldix
    Copy-Item -LiteralPath (Join-Path $Destination 'LhaForge.ini.template') -Destination (Join-Path $Destination 'LhaForge.ini') -Force
    Copy-Item -LiteralPath (Join-Path $Destination 'LFCaldix.ini.template') -Destination (Join-Path $Destination 'LFCaldix.ini') -Force
    New-Item -ItemType Directory -Path (Join-Path $Destination 'results') -Force | Out-Null

    return [pscustomobject]@{
        exe = Get-FileEvidence -Path (Join-Path $Destination 'LhaForge.exe')
        dll = Get-FileEvidence -Path (Join-Path $Destination '7-ZIP32.DLL')
    }
}

$OriginalExe = [System.IO.Path]::GetFullPath($OriginalExe)
$SevenZipDll = [System.IO.Path]::GetFullPath($SevenZipDll)

if (-not (Test-Path -LiteralPath $OriginalExe -PathType Leaf)) {
    throw ('Original LhaForge.exe was not found: {0}' -f $OriginalExe)
}
if (-not (Test-Path -LiteralPath $SevenZipDll -PathType Leaf)) {
    throw ('7-ZIP32.DLL was not found: {0}' -f $SevenZipDll)
}
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw ('Build helper was not found: {0}' -f $buildScript)
}

$sourceDllEvidence = Get-FileEvidence -Path $SevenZipDll
if ($sourceDllEvidence.peMachine -ne '0x014c') {
    throw ('7-ZIP32.DLL is not Win32/x86: {0}' -f $SevenZipDll)
}

Write-Host ('[POC2-ARCHIVE] Building modern {0}|Win32...' -f $ModernConfiguration)
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
        throw ('PoC 2-B output already exists. Review it or rerun with -Force: {0}' -f $outputRoot)
    }
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $kitRoot -Force | Out-Null

$fixtureRoot = Join-Path $kitRoot 'fixture'
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$fixtureEvidence = New-Fixture -Root $fixtureRoot

$original = Stage-Target -SourceExe $OriginalExe -SourceDll $SevenZipDll -Destination (Join-Path $kitRoot 'original')
$modern = Stage-Target -SourceExe $modernExe -SourceDll $SevenZipDll -Destination (Join-Path $kitRoot 'modern')

if ($original.exe.peMachine -ne '0x014c') {
    throw ('Original binary is not Win32/x86: {0}' -f $original.exe.path)
}
if ($modern.exe.peMachine -ne '0x014c') {
    throw ('Modern binary is not Win32/x86: {0}' -f $modern.exe.path)
}
if ($original.dll.sha256 -ne $modern.dll.sha256) {
    throw 'Original and Modern DLL hashes differ.'
}
if ($original.dll.sha256 -ne $sourceDllEvidence.sha256) {
    throw 'Staged DLL hash differs from the selected source DLL.'
}

$kitScriptRoot = Join-Path $kitRoot 'scripts'
New-Item -ItemType Directory -Path $kitScriptRoot -Force | Out-Null
foreach ($name in @(
    'common.ps1',
    'initialize-archive-regression.ps1',
    'run-archive-operation.ps1',
    'capture-archive-result.ps1',
    'compare-archive-results.ps1'
)) {
    Copy-Item -LiteralPath (Join-Path $vmScriptRoot $name) -Destination (Join-Path $kitScriptRoot $name) -Force
}
Copy-Item -LiteralPath (Join-Path $vmScriptRoot 'CHECKLIST.md') -Destination (Join-Path $kitRoot 'CHECKLIST.md') -Force

$manifest = [ordered]@{
    schemaVersion = 1
    preparedUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'PoC 2-B archive basic operation regression VM kit'
    modernConfiguration = $ModernConfiguration
    original = $original
    modern = $modern
    sevenZipDllSource = $sourceDllEvidence
    fixture = $fixtureEvidence
    fixedCompression = [ordered]@{
        format = 'zip'
        method = 'Deflate'
        level = '5'
        ignoreTopDirectory = $true
    }
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $kitRoot 'manifest.json') -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $kitRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ''
Write-Host '[POC2-ARCHIVE] VM kit prepared.'
Write-Host ('[POC2-ARCHIVE] Directory: {0}' -f $kitRoot)
Write-Host ('[POC2-ARCHIVE] ZIP      : {0}' -f $zipPath)
Write-Host ''
Write-Host '[POC2-ARCHIVE] 7-ZIP32.DLL evidence'
Write-Host ('  Version : {0}' -f $sourceDllEvidence.fileVersion)
Write-Host ('  Product : {0}' -f $sourceDllEvidence.productVersion)
Write-Host ('  PE      : {0} ({1})' -f $sourceDllEvidence.peMachine, $sourceDllEvidence.architecture)
Write-Host ('  SHA-256 : {0}' -f $sourceDllEvidence.sha256)
Write-Host ''
Write-Host '[POC2-ARCHIVE] Reference ZIP'
Write-Host ('  SHA-256 : {0}' -f $fixtureEvidence.referenceZip.sha256)
Write-Host ('  Entries : {0}' -f $fixtureEvidence.referenceZipEntries.entries.Count)
Write-Host ''
Write-Host '[POC2-ARCHIVE] Copy the ZIP to the Windows VM local fixed disk, extract it, and read CHECKLIST.md.'
