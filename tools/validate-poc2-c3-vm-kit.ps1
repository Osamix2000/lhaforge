#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$KitRoot,
    [string]$ZipPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($KitRoot)) {
    $KitRoot = Join-Path $repoRoot '.baseline\poc2-encoding\c3-vm-kit'
}
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $ZipPath = Join-Path $repoRoot '.baseline\poc2-encoding\poc2-c3-vm-kit.zip'
}
$KitRoot = [System.IO.Path]::GetFullPath($KitRoot)
$ZipPath = [System.IO.Path]::GetFullPath($ZipPath)

$psv = [version]$PSVersionTable.PSVersion
if ([string]$PSVersionTable.PSEdition -cne 'Desktop' -or $psv.Major -ne 5 -or $psv.Minor -ne 1) {
    throw ('PoC 2-C3 VM kit validation requires Windows PowerShell 5.1 exactly. Current: {0} / {1}' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
}

function Read-JsonStrict {
    param([Parameter(Mandatory = $true)][string]$Path)
    $enc = New-Object System.Text.UTF8Encoding($false, $true)
    return ([System.IO.File]::ReadAllText($Path, $enc) | ConvertFrom-Json)
}

function Get-PeMachineLocal {
    param([Parameter(Mandatory = $true)][string]$Path)
    $s = [System.IO.File]::OpenRead($Path)
    try {
        $r = New-Object System.IO.BinaryReader($s)
        try {
            if ($r.ReadUInt16() -ne 0x5A4D) { throw ('Not PE: {0}' -f $Path) }
            $s.Position = 0x3C
            $off = $r.ReadInt32()
            $s.Position = $off
            if ($r.ReadUInt32() -ne 0x00004550) { throw ('Missing PE signature: {0}' -f $Path) }
            return $r.ReadUInt16()
        }
        finally { $r.Dispose() }
    }
    finally { $s.Dispose() }
}

$frozen = @(
        [pscustomobject]@{ id = 'ascii'; behaviorClass = 'spec-valid'; sha256 = 'ce18a398ab39e50f4215c76132602888b59612be150c5c1f46cd2316ef161e2a' },
        [pscustomobject]@{ id = 'utf8-japanese'; behaviorClass = 'spec-valid'; sha256 = '3157c1131c0bb9fd09802e3716a6892482101f133b089717c1731e4a48bfb12b' },
        [pscustomobject]@{ id = 'utf8-emoji'; behaviorClass = 'spec-valid'; sha256 = '2917aeef94e2f0b130fc9978fc55968643243c1857c338aec700d641905b5298' },
        [pscustomobject]@{ id = 'utf8-nfc'; behaviorClass = 'spec-valid'; sha256 = '0c5523eda6b603eaa0c19d5a55e78a6255e045a4e96d4915639d8c535c95b51d' },
        [pscustomobject]@{ id = 'utf8-nfd'; behaviorClass = 'spec-valid'; sha256 = '7604c32e7c24626a65df4fcfcc48ceddd8c68cca08009bcc2f632f4e9fbd77cd' },
        [pscustomobject]@{ id = 'cp932-japanese'; behaviorClass = 'legacy-observe'; sha256 = 'a3937ae3d1ce93464f754e788187f5c7727e47cb8e542695e9735f8fa4bfabe4' },
        [pscustomobject]@{ id = 'cp932-ambiguous'; behaviorClass = 'legacy-observe'; sha256 = 'b70295e558d4e32c8c6afeb24a89c1ade8753b85b69b3b605df44c7bcc113a9b' },
        [pscustomobject]@{ id = 'cp932-upath-valid'; behaviorClass = 'metadata-observe'; sha256 = 'ce769489ef71130a0ee1a9893b51e768825f235f6b396684f9b87bce2bd9667c' },
        [pscustomobject]@{ id = 'cp932-upath-bad-crc'; behaviorClass = 'metadata-observe'; sha256 = '4590a945bc06557628ecea0a1b28d18ea69645a263ff6de22ca7d57f6232f456' },
        [pscustomobject]@{ id = 'cp932-upath-conflict'; behaviorClass = 'conflict-observe'; sha256 = 'f02a51af7bc966d503355479cabd1a5ed32956fd4c4b72039ff7f40b7f7357a9' },
        [pscustomobject]@{ id = 'utf8-upath-conflict'; behaviorClass = 'conflict-observe'; sha256 = 'ef9d577380b5eda37a76a1cf4712311a68323f13971b89b111676ed2066fc93b' },
        [pscustomobject]@{ id = 'invalid-utf8-flag'; behaviorClass = 'malformed-observe'; sha256 = 'f5a66a68d901a9f0c98f16aecd3df696cebd1f2009aaa04b02fff5394f69dcb8' },
        [pscustomobject]@{ id = 'upath-invalid-utf8'; behaviorClass = 'malformed-observe'; sha256 = '8717cbc1e393b46638cd5d6a8728e654b7d0c4d912004ea12229641aa4e21bcb' },
        [pscustomobject]@{ id = 'upath-unknown-version'; behaviorClass = 'malformed-observe'; sha256 = '4f34cccf47f14a653dece50e0b4591f73e46d4b8b417a604048631a5f78aa211' },
        [pscustomobject]@{ id = 'macos-metadata'; behaviorClass = 'cross-platform-observe'; sha256 = '0668be22ca3671dc21bba6e69be000b024727eff156324a109ae18fe59ec0021' }
)

if (-not (Test-Path -LiteralPath $KitRoot -PathType Container)) {
    throw ('Kit root was not found: {0}' -f $KitRoot)
}
if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw ('Kit ZIP was not found: {0}' -f $ZipPath)
}

$required = @(
    'manifest.json',
    'C3-CHECKLIST.md',
    'original\LhaForge.exe',
    'original\7-ZIP32.DLL',
    'modern\LhaForge.exe',
    'modern\7-ZIP32.DLL',
    'fixture-c3\fixture-manifest.json',
    'scripts\common.ps1',
    'scripts\c3-common.ps1',
    'scripts\initialize-c3-regression.ps1',
    'scripts\run-c3-case.ps1',
    'scripts\run-c3-target.ps1',
    'scripts\capture-c3-result.ps1',
    'scripts\compare-c3-results.ps1'
)
foreach ($rel in $required) {
    $p = Join-Path $KitRoot $rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('Required kit file is missing: {0}' -f $p)
    }
}

$manifest = Read-JsonStrict -Path (Join-Path $KitRoot 'manifest.json')
if (@($manifest.c3Cases).Count -ne 15) {
    throw ('Kit manifest C3 case count mismatch: {0}' -f @($manifest.c3Cases).Count)
}

$fixedDll = 'a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c'
foreach ($target in @('original', 'modern')) {
    $exe = Join-Path $KitRoot ($target + '\LhaForge.exe')
    $dll = Join-Path $KitRoot ($target + '\7-ZIP32.DLL')
    if ((Get-PeMachineLocal -Path $exe) -ne 0x014c) { throw ('{0} EXE is not x86.' -f $target) }
    if ((Get-PeMachineLocal -Path $dll) -ne 0x014c) { throw ('{0} DLL is not x86.' -f $target) }
    $dllHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($dllHash -cne $fixedDll) { throw ('{0} fixed backend hash mismatch.' -f $target) }
    $exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($exeHash -cne [string]$manifest.$target.exe.sha256) { throw ('{0} EXE hash differs from manifest.' -f $target) }
}

$fixtureManifest = Read-JsonStrict -Path (Join-Path $KitRoot 'fixture-c3\fixture-manifest.json')
if (@($fixtureManifest.cases).Count -ne 15) {
    throw ('Fixture manifest case count mismatch: {0}' -f @($fixtureManifest.cases).Count)
}

foreach ($case in $frozen) {
    $path = Join-Path $KitRoot ('fixture-c3\' + $case.id + '.zip')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('Fixture is missing: {0}' -f $path)
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne [string]$case.sha256) {
        throw ('Fixture hash mismatch: {0}' -f $case.id)
    }

    $fm = @($fixtureManifest.cases | Where-Object { [string]$_.id -ceq [string]$case.id })
    if ($fm.Count -ne 1 -or [string]$fm[0].sha256 -cne [string]$case.sha256) {
        throw ('Fixture manifest identity mismatch: {0}' -f $case.id)
    }
}

$parseIssues = New-Object System.Collections.ArrayList
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $KitRoot 'scripts') -Filter '*.ps1' -File | Sort-Object Name) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    foreach ($err in @($errors)) {
        [void]$parseIssues.Add(('{0}: {1}' -f $script.Name, $err.Message))
    }
}
if ($parseIssues.Count -ne 0) {
    throw ('PowerShell parser validation failed:`n  ' + ($parseIssues -join "`n  "))
}

# Exercise C3 helper functions on the Host without launching LhaForge.
. (Join-Path $KitRoot 'scripts\common.ps1')
. (Join-Path $KitRoot 'scripts\c3-common.ps1')

[byte[]]$emptyBytes = Convert-C3HexToBytes -Hex ''
if ($emptyBytes.Length -ne 0) {
    throw 'C3 helper empty hex conversion smoke test failed.'
}

$badUtf8 = Get-C3StrictUtf8 -Bytes ([byte[]]@(0xE3, 0x28, 0xA1))
if ([bool]$badUtf8.valid) {
    throw 'C3 helper strict UTF-8 rejection smoke test failed.'
}

$asciiCase = @($fixtureManifest.cases | Where-Object { [string]$_.id -ceq 'ascii' })[0]
$asciiCandidates = @(Get-C3NameCandidates -FixtureCase $asciiCase)
if ($asciiCandidates.Count -ne 1 -or [string]$asciiCandidates[0].text -cne 'ascii.txt') {
    throw 'C3 helper ASCII candidate smoke test failed.'
}

$conflictCase = @($fixtureManifest.cases | Where-Object { [string]$_.id -ceq 'cp932-upath-conflict' })[0]
$conflictCandidates = @(Get-C3NameCandidates -FixtureCase $conflictCase)
if ($conflictCandidates.Count -lt 2) {
    throw 'C3 helper conflict candidate smoke test failed.'
}

$macCase = @($fixtureManifest.cases | Where-Object { [string]$_.id -ceq 'macos-metadata' })[0]
$macExpected = Get-C3ExpectedSemanticInventory -FixtureCase $macCase
if ($null -eq $macExpected -or @($macExpected.entries).Count -ne 4) {
    throw 'C3 helper macOS semantic inventory smoke test failed.'
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$stream = [System.IO.File]::OpenRead($ZipPath)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $dups = @($names | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($dups.Count -ne 0) { throw 'VM kit ZIP contains duplicate entry paths.' }

        foreach ($name in $names) {
            if ($name.StartsWith('/') -or $name.StartsWith('\') -or $name -match '(^|/)\.\.(/|$)') {
                throw ('Unsafe VM kit ZIP path: {0}' -f $name)
            }
        }

        foreach ($rel in $required) {
            $want = $rel.Replace('\', '/')
            if ($names -notcontains $want) {
                throw ('Required file is missing from VM kit ZIP: {0}' -f $want)
            }
        }

        foreach ($case in $frozen) {
            $want = 'fixture-c3/' + $case.id + '.zip'
            if ($names -notcontains $want) {
                throw ('Fixture is missing from VM kit ZIP: {0}' -f $want)
            }
        }
    }
    finally { $zip.Dispose() }
}
finally { $stream.Dispose() }

$zipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host '[POC2-C3] Formal VM kit Host validation PASS.'
Write-Host ('[POC2-C3] Kit root : {0}' -f $KitRoot)
Write-Host ('[POC2-C3] ZIP      : {0}' -f $ZipPath)
Write-Host ('[POC2-C3] ZIP SHA  : {0}' -f $zipHash)
Write-Host '[POC2-C3] Fixtures : 15 / 15'
Write-Host '[POC2-C3] PS parser: PASS'
Write-Host '[POC2-C3] Runtime helpers: PASS'
Write-Host '[POC2-C3] ZIP paths: duplicate=0 / unsafe=0'
