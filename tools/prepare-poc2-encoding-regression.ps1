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
$vmScriptRoot = Join-Path $PSScriptRoot 'poc2-encoding-vm'
$outputRoot = Join-Path $repoRoot '.baseline\poc2-encoding'
$kitRoot = Join-Path $outputRoot 'vm-kit'
$zipPath = Join-Path $outputRoot 'poc2-encoding-vm-kit.zip'
$expectedSevenZipSha256 = 'a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c'

. (Join-Path $vmScriptRoot 'common.ps1')
. (Join-Path $vmScriptRoot 'response-common.ps1')
. (Join-Path $vmScriptRoot 'abnormal-response-common.ps1')

$preparePsVersion = [version]$PSVersionTable.PSVersion
if (
    [string]$PSVersionTable.PSEdition -cne 'Desktop' -or
    $preparePsVersion.Major -ne 5 -or
    $preparePsVersion.Minor -ne 1
) {
    throw ('PoC 2-C VM kit generation requires Windows PowerShell 5.1 exactly. Current runtime: PowerShell {0}, PSEdition {1}.' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
}

Assert-Poc2C2EncodingByteGenerator
Assert-Poc2C2AbnormalByteGenerator
Write-Host '[POC2-ENC] C2 normal/abnormal byte generator smoke tests passed.'

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

$repoStatus = @(& git -C $repoRoot status --porcelain)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read repository working-tree status.'
}
if ($repoStatus.Count -ne 0) {
    throw 'PoC 2-C VM kit generation requires a clean repository working tree. Commit or intentionally discard all changes before generating the formal VM kit.'
}

$sourceDllEvidence = Get-FileEvidence -Path $SevenZipDll
if ($sourceDllEvidence.peMachine -ne '0x014c') {
    throw ('7-ZIP32.DLL is not Win32/x86: {0}' -f $SevenZipDll)
}
if ($sourceDllEvidence.sha256 -cne $expectedSevenZipSha256) {
    throw ('PoC 2-C requires the fixed PoC 2-B 7-ZIP32.DLL bytes. Actual SHA-256: {0}' -f $sourceDllEvidence.sha256)
}

Write-Host ('[POC2-ENC] Building modern {0}|Win32...' -f $ModernConfiguration)
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
        throw ('PoC 2-C output already exists. Review it or rerun with -Force: {0}' -f $outputRoot)
    }
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $kitRoot -Force | Out-Null

$original = Stage-Target -SourceExe $OriginalExe -SourceDll $SevenZipDll -Destination (Join-Path $kitRoot 'original')
$modern = Stage-Target -SourceExe $modernExe -SourceDll $SevenZipDll -Destination (Join-Path $kitRoot 'modern')

if ($original.exe.peMachine -ne '0x014c') {
    throw ('Original binary is not Win32/x86: {0}' -f $original.exe.path)
}
if ($modern.exe.peMachine -ne '0x014c') {
    throw ('Modern binary is not Win32/x86: {0}' -f $modern.exe.path)
}
if ($original.dll.sha256 -cne $modern.dll.sha256) {
    throw 'Original and Modern DLL hashes differ.'
}

$kitScriptRoot = Join-Path $kitRoot 'scripts'
New-Item -ItemType Directory -Path $kitScriptRoot -Force | Out-Null
foreach ($name in @(
    'common.ps1',
    'response-common.ps1',
    'abnormal-response-common.ps1',
    'initialize-encoding-regression.ps1',
    'run-encoding-case.ps1',
    'capture-encoding-result.ps1',
    'compare-encoding-results.ps1',
    'initialize-response-regression.ps1',
    'run-response-case.ps1',
    'capture-response-result.ps1',
    'compare-response-results.ps1',
    'initialize-response-abnormal-regression.ps1',
    'run-response-abnormal-case.ps1',
    'capture-response-abnormal-result.ps1',
    'compare-response-abnormal-results.ps1'
)) {
    Copy-Item -LiteralPath (Join-Path $vmScriptRoot $name) -Destination (Join-Path $kitScriptRoot $name) -Force
}
Copy-Item -LiteralPath (Join-Path $vmScriptRoot 'CHECKLIST.md') -Destination (Join-Path $kitRoot 'CHECKLIST.md') -Force
Copy-Item -LiteralPath (Join-Path $vmScriptRoot 'RESPONSE-CHECKLIST.md') -Destination (Join-Path $kitRoot 'RESPONSE-CHECKLIST.md') -Force
Copy-Item -LiteralPath (Join-Path $vmScriptRoot 'RESPONSE-ABNORMAL-CHECKLIST.md') -Destination (Join-Path $kitRoot 'RESPONSE-ABNORMAL-CHECKLIST.md') -Force

$repoHead = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoHead)) {
    throw 'Could not read repository HEAD.'
}

$caseManifest = @()
foreach ($case in Get-Poc2C1Cases) {
    $caseManifest += [ordered]@{
        id = $case.id
        codePoints = @($case.codePoints | ForEach-Object { 'U+{0:X}' -f $_ })
    }
}

$responseCaseManifest = @()
foreach ($case in Get-Poc2C2Cases) {
    $responseCaseManifest += [ordered]@{
        id = $case.id
        argumentPlan = @($case.argumentPlan)
    }
}

$responseAbnormalCaseManifest = @()
foreach ($case in Get-Poc2C2AbnormalCases) {
    $responseAbnormalCaseManifest += [ordered]@{
        id = $case.id
        fixtureKind = $case.fixtureKind
        argumentPlan = @($case.argumentPlan)
        expectationMode = $case.expectation.mode
        highRisk = [bool]$case.expectation.highRisk
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    preparedUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'PoC 2-C encoding and path regression VM kit (C1 + C2 normal + C2 abnormal tooling)'
    repoHead = $repoHead
    modernConfiguration = $ModernConfiguration
    original = $original
    modern = $modern
    fixedBackend = $sourceDllEvidence
    cases = @($caseManifest)
    responseCases = @($responseCaseManifest)
    responseAbnormalCases = @($responseAbnormalCaseManifest)
    fixtureGeneration = 'Generated inside the VM from ASCII-only PowerShell code points/raw byte builders.'
}
Write-JsonUtf8NoBom -Value $manifest -Path (Join-Path $kitRoot 'manifest.json') -Depth 20

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $kitRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

$kitZipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host ''
Write-Host '[POC2-ENC] PoC 2-C VM kit prepared.'
Write-Host ('[POC2-ENC] Directory: {0}' -f $kitRoot)
Write-Host ('[POC2-ENC] ZIP      : {0}' -f $zipPath)
Write-Host ('[POC2-ENC] ZIP SHA  : {0}' -f $kitZipHash)
Write-Host ('[POC2-ENC] Repo HEAD: {0}' -f $repoHead)
Write-Host ''
Write-Host '[POC2-ENC] Fixed 7-ZIP32.DLL'
Write-Host ('  Version : {0}' -f $sourceDllEvidence.fileVersion)
Write-Host ('  PE      : {0} ({1})' -f $sourceDllEvidence.peMachine, $sourceDllEvidence.architecture)
Write-Host ('  SHA-256 : {0}' -f $sourceDllEvidence.sha256)
Write-Host ''
Write-Host '[POC2-ENC] The VM kit contains ASCII paths only.'
Write-Host '[POC2-ENC] Unicode fixture names and C2 normal response content are generated inside the VM from code points.'
Write-Host '[POC2-ENC] C2 abnormal response files are generated inside the VM from explicit raw byte builders.'
Write-Host '[POC2-ENC] Copy the ZIP to the Windows VM local fixed disk, extract it, and read CHECKLIST.md / RESPONSE-CHECKLIST.md / RESPONSE-ABNORMAL-CHECKLIST.md.'
