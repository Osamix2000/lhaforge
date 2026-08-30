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
$c3HostRoot = Join-Path $PSScriptRoot 'poc2-encoding-c3-host'
$outputRoot = Join-Path $repoRoot '.baseline\poc2-encoding'
$fixtureRoot = Join-Path $outputRoot 'c3-fixtures'
$kitRoot = Join-Path $outputRoot 'c3-vm-kit'
$zipPath = Join-Path $outputRoot 'poc2-c3-vm-kit.zip'
$expectedSevenZipSha256 = 'a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c'

. (Join-Path $vmScriptRoot 'common.ps1')
. (Join-Path $vmScriptRoot 'c3-common.ps1')

$psv = [version]$PSVersionTable.PSVersion
if ([string]$PSVersionTable.PSEdition -cne 'Desktop' -or $psv.Major -ne 5 -or $psv.Minor -ne 1) {
    throw ('PoC 2-C3 formal kit generation requires Windows PowerShell 5.1 exactly. Current: {0} / {1}' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
}

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

foreach ($path in @($OriginalExe, $SevenZipDll, $buildScript, (Join-Path $c3HostRoot 'generate-fixtures.ps1'), (Join-Path $c3HostRoot 'validate-fixtures.ps1'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Required file was not found: {0}' -f $path)
    }
}

$repoStatus = @(& git -C $repoRoot status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Could not read repository working-tree status.' }
if ($repoStatus.Count -ne 0) {
    throw 'PoC 2-C3 formal kit generation requires a clean repository working tree.'
}

$sourceDllEvidence = Get-FileEvidence -Path $SevenZipDll
if ($sourceDllEvidence.peMachine -ne '0x014c') {
    throw ('7-ZIP32.DLL is not Win32/x86: {0}' -f $SevenZipDll)
}
if ($sourceDllEvidence.sha256 -cne $expectedSevenZipSha256) {
    throw ('PoC 2-C3 requires the fixed 7-ZIP32.DLL bytes. Actual SHA-256: {0}' -f $sourceDllEvidence.sha256)
}

Write-Host '[POC2-C3] Regenerating frozen host fixtures...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $c3HostRoot 'generate-fixtures.ps1') -OutputRoot $fixtureRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $c3HostRoot 'validate-fixtures.ps1') -FixtureRoot $fixtureRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$fixtureManifestPath = Join-Path $fixtureRoot 'fixture-manifest.json'
$fixtureManifest = Read-JsonUtf8 -Path $fixtureManifestPath
foreach ($frozen in Get-Poc2C3FrozenCases) {
    $m = @($fixtureManifest.cases | Where-Object { [string]$_.id -ceq [string]$frozen.id })
    if ($m.Count -ne 1) { throw ('Fixture manifest mismatch for case: {0}' -f $frozen.id) }
    if ([string]$m[0].sha256 -cne [string]$frozen.sha256) {
        throw ('Frozen fixture hash mismatch in manifest for case: {0}' -f $frozen.id)
    }
}

Write-Host ('[POC2-C3] Building modern {0}|Win32...' -f $ModernConfiguration)
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

if (Test-Path -LiteralPath $kitRoot) {
    if (-not $Force) {
        throw ('PoC 2-C3 VM kit already exists. Review it or rerun with -Force: {0}' -f $kitRoot)
    }
    Remove-Item -LiteralPath $kitRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    if (-not $Force) {
        throw ('PoC 2-C3 VM kit ZIP already exists. Review it or rerun with -Force: {0}' -f $zipPath)
    }
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $kitRoot -Force | Out-Null

$original = Stage-Target -SourceExe $OriginalExe -SourceDll $SevenZipDll -Destination (Join-Path $kitRoot 'original')
$modern = Stage-Target -SourceExe $modernExe -SourceDll $SevenZipDll -Destination (Join-Path $kitRoot 'modern')

if ($original.exe.peMachine -ne '0x014c') { throw 'Original binary is not Win32/x86.' }
if ($modern.exe.peMachine -ne '0x014c') { throw 'Modern binary is not Win32/x86.' }
if ($original.dll.sha256 -cne $modern.dll.sha256) { throw 'Original and Modern DLL hashes differ.' }

$kitFixtureRoot = Join-Path $kitRoot 'fixture-c3'
Copy-Item -LiteralPath $fixtureRoot -Destination $kitFixtureRoot -Recurse -Force

$kitScriptRoot = Join-Path $kitRoot 'scripts'
New-Item -ItemType Directory -Path $kitScriptRoot -Force | Out-Null
foreach ($name in @(
    'common.ps1',
    'c3-common.ps1',
    'initialize-c3-regression.ps1',
    'run-c3-case.ps1',
    'run-c3-target.ps1',
    'capture-c3-result.ps1',
    'compare-c3-results.ps1'
)) {
    Copy-Item -LiteralPath (Join-Path $vmScriptRoot $name) -Destination (Join-Path $kitScriptRoot $name) -Force
}
Copy-Item -LiteralPath (Join-Path $vmScriptRoot 'C3-CHECKLIST.md') -Destination (Join-Path $kitRoot 'C3-CHECKLIST.md') -Force

$repoHead = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoHead)) {
    throw 'Could not read repository HEAD.'
}

$c3Cases = @()
foreach ($case in Get-Poc2C3FrozenCases) {
    $c3Cases += [ordered]@{
        id = [string]$case.id
        behaviorClass = [string]$case.behaviorClass
        sha256 = [string]$case.sha256
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    preparedUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'PoC 2-C3 ZIP entry-name metadata formal VM kit'
    repoHead = $repoHead
    modernConfiguration = $ModernConfiguration
    original = $original
    modern = $modern
    fixedBackend = $sourceDllEvidence
    fixtureManifestSha256 = (Get-FileHash -LiteralPath $fixtureManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    c3Cases = @($c3Cases)
    fixtureGeneration = 'Generated and independently validated on the Host with tracked PoC 2-C3 raw ZIP tooling before packaging.'
}
Write-JsonUtf8NoBom -Value $manifest -Path (Join-Path $kitRoot 'manifest.json') -Depth 20

Compress-Archive -Path (Join-Path $kitRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

$kitZipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host ''
Write-Host '[POC2-C3] Formal VM kit prepared.'
Write-Host ('[POC2-C3] Directory: {0}' -f $kitRoot)
Write-Host ('[POC2-C3] ZIP      : {0}' -f $zipPath)
Write-Host ('[POC2-C3] ZIP SHA  : {0}' -f $kitZipHash)
Write-Host ('[POC2-C3] Repo HEAD: {0}' -f $repoHead)
Write-Host ('[POC2-C3] Fixtures : {0}' -f $c3Cases.Count)
Write-Host '[POC2-C3] Do not run the VM yet if this is a Host-only work session.'
Write-Host '[POC2-C3] Next Host gate: validate-poc2-c3-vm-kit.ps1'
