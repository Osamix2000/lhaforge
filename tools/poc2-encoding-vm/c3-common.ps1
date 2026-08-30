#Requires -Version 5.1
Set-StrictMode -Version 2.0

function Get-Poc2C3FrozenCases {
    return @(
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
}

function Get-Poc2C3FrozenCase {
    param([Parameter(Mandatory = $true)][string]$CaseId)

    $matches = @(Get-Poc2C3FrozenCases | Where-Object { $_.id -ceq $CaseId })
    if ($matches.Count -ne 1) {
        throw ('Unknown PoC 2-C3 case id: {0}' -f $CaseId)
    }
    return $matches[0]
}

function Get-C3FixtureRoot {
    return (Join-Path (Get-KitRoot) 'fixture-c3')
}

function Get-C3FixtureManifest {
    $path = Join-Path (Get-C3FixtureRoot) 'fixture-manifest.json'
    return (Read-JsonUtf8 -Path $path)
}

function Get-C3FixtureCase {
    param([Parameter(Mandatory = $true)][string]$CaseId)

    $manifest = Get-C3FixtureManifest
    $matches = @($manifest.cases | Where-Object { [string]$_.id -ceq $CaseId })
    if ($matches.Count -ne 1) {
        throw ('C3 fixture manifest case was not found exactly once: {0}' -f $CaseId)
    }
    return $matches[0]
}

function Get-C3FixturePath {
    param([Parameter(Mandatory = $true)][string]$CaseId)
    return (Join-Path (Get-C3FixtureRoot) ($CaseId + '.zip'))
}

function Assert-C3FixtureIdentity {
    param([Parameter(Mandatory = $true)][string]$CaseId)

    $frozen = Get-Poc2C3FrozenCase -CaseId $CaseId
    $path = Get-C3FixturePath -CaseId $CaseId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ('C3 fixture is missing: {0}' -f $path)
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne [string]$frozen.sha256) {
        throw ('C3 fixture SHA-256 mismatch for {0}. Actual={1} Expected={2}' -f $CaseId, $actual, $frozen.sha256)
    }

    return [pscustomobject]@{
        id = $CaseId
        path = $path
        sha256 = $actual
        behaviorClass = [string]$frozen.behaviorClass
    }
}

function Get-C3RunRecordRoot {
    param([Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target)
    return (Join-Path (Get-TargetRoot -Target $Target) 'results\c3-run-records')
}

function Get-C3RunRecordPath {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
        [Parameter(Mandatory = $true)][ValidateSet('list', 'test', 'extract')][string]$Operation,
        [Parameter(Mandatory = $true)][string]$CaseId
    )
    return (Join-Path (Get-C3RunRecordRoot -Target $Target) ($Operation + '-' + $CaseId + '.json'))
}

function Save-C3RunRecord {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
        [Parameter(Mandatory = $true)][ValidateSet('list', 'test', 'extract')][string]$Operation,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [Parameter(Mandatory = $true)]$Record
    )

    $root = Get-C3RunRecordRoot -Target $Target
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $path = Get-C3RunRecordPath -Target $Target -Operation $Operation -CaseId $CaseId
    Write-JsonUtf8NoBom -Value $Record -Path $path -Depth 24
    return $path
}

function Convert-C3HexToBytes {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Hex)

    if ([string]::IsNullOrEmpty($Hex)) {
        return ,([byte[]]@())
    }
    if (($Hex.Length % 2) -ne 0 -or $Hex -notmatch '^[0-9A-Fa-f]+$') {
        throw ('Invalid hex byte string: {0}' -f $Hex)
    }

    [byte[]]$bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    Write-Output -NoEnumerate $bytes
}

function Get-C3StrictUtf8 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $enc = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $text = $enc.GetString($Bytes)
        return [pscustomobject]@{
            valid = $true
            text = $text
            codePoints = @(Get-CodePointStrings -Text $text)
        }
    }
    catch {
        return [pscustomobject]@{
            valid = $false
            text = $null
            codePoints = @()
        }
    }
}

function Get-C3StrictCp932 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $encoderFallback = New-Object System.Text.EncoderExceptionFallback
    $decoderFallback = New-Object System.Text.DecoderExceptionFallback
    $enc = [System.Text.Encoding]::GetEncoding(932, $encoderFallback, $decoderFallback)
    try {
        $text = $enc.GetString($Bytes)
        return [pscustomobject]@{
            valid = $true
            text = $text
            codePoints = @(Get-CodePointStrings -Text $text)
        }
    }
    catch {
        return [pscustomobject]@{
            valid = $false
            text = $null
            codePoints = @()
        }
    }
}

function Get-C3UnicodePathCandidate {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$ExtraHex)

    [byte[]]$bytes = Convert-C3HexToBytes -Hex $ExtraHex
    $offset = 0
    while (($offset + 4) -le $bytes.Length) {
        $id = [uint16]($bytes[$offset] -bor ($bytes[$offset + 1] -shl 8))
        $size = [uint16]($bytes[$offset + 2] -bor ($bytes[$offset + 3] -shl 8))
        $offset += 4
        if (($offset + $size) -gt $bytes.Length) {
            return $null
        }

        if ($id -eq 0x7075 -and $size -ge 5) {
            $version = [int]$bytes[$offset]
            $nameLength = $size - 5
            [byte[]]$nameBytes = New-Object byte[] $nameLength
            if ($nameLength -gt 0) {
                [Array]::Copy($bytes, $offset + 5, $nameBytes, 0, $nameLength)
            }
            $decoded = Get-C3StrictUtf8 -Bytes $nameBytes
            return [pscustomobject]@{
                present = $true
                version = $version
                validUtf8 = [bool]$decoded.valid
                text = $decoded.text
                codePoints = @($decoded.codePoints)
            }
        }
        $offset += $size
    }
    return $null
}

function Get-C3NameCandidates {
    param([Parameter(Mandatory = $true)]$FixtureCase)

    $result = New-Object System.Collections.ArrayList
    if (@($FixtureCase.entries).Count -ne 1) {
        return @()
    }

    $entry = @($FixtureCase.entries)[0]
    [byte[]]$raw = Convert-C3HexToBytes -Hex ([string]$entry.nameHex)

    $cp932 = Get-C3StrictCp932 -Bytes $raw
    if ($cp932.valid) {
        [void]$result.Add([pscustomobject]@{
            key = 'raw-cp932'
            text = [string]$cp932.text
            codePoints = @($cp932.codePoints)
        })
    }

    $utf8 = Get-C3StrictUtf8 -Bytes $raw
    if ($utf8.valid) {
        [void]$result.Add([pscustomobject]@{
            key = 'raw-utf8'
            text = [string]$utf8.text
            codePoints = @($utf8.codePoints)
        })
    }

    $upath = Get-C3UnicodePathCandidate -ExtraHex ([string]$entry.extraHex)
    if ($null -ne $upath -and $upath.validUtf8) {
        [void]$result.Add([pscustomobject]@{
            key = 'upath-utf8'
            text = [string]$upath.text
            codePoints = @($upath.codePoints)
        })
    }

    $dedup = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($item in $result) {
        $signature = (($item.codePoints) -join ',')
        if (-not $seen.ContainsKey($signature)) {
            $seen[$signature] = $true
            [void]$dedup.Add($item)
        }
    }
    return @($dedup)
}

function Get-C3DirectoryInventory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
            directories = @()
            files = @()
            fingerprint = $null
        }
    }

    $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    $dirs = @()
    foreach ($dir in Get-ChildItem -LiteralPath $root -Recurse -Force -Directory | Sort-Object FullName) {
        $relative = $dir.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $dirs += [pscustomobject]@{
            relativePath = $relative
            unicode = Get-UnicodeStringEvidence -Text $relative
        }
    }

    $files = @()
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $files += [pscustomobject]@{
            relativePath = $relative
            unicode = Get-UnicodeStringEvidence -Text $relative
            sizeBytes = [Int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    $canonical = @()
    foreach ($dir in ($dirs | Sort-Object relativePath)) {
        $canonical += ('D|{0}' -f (($dir.unicode.codePoints) -join ','))
    }
    foreach ($file in ($files | Sort-Object relativePath)) {
        $canonical += ('F|{0}|{1}|{2}' -f (($file.unicode.codePoints) -join ','), $file.sizeBytes, $file.sha256)
    }

    return [pscustomobject]@{
        path = $root
        exists = $true
        directories = @($dirs)
        files = @($files)
        fingerprint = Get-StringSha256 -Text ($canonical -join "`n")
    }
}

function Get-C3ExpectedSemanticInventory {
    param([Parameter(Mandatory = $true)]$FixtureCase)

    $lines = @()
    foreach ($entry in @($FixtureCase.entries)) {
        $name = [string]$entry.semanticName
        if ([string]::IsNullOrEmpty($name)) {
            return $null
        }

        if ($name.EndsWith('/')) {
            $trimmed = $name.TrimEnd('/')
            $lines += ('D|{0}' -f ((Get-CodePointStrings -Text $trimmed) -join ','))
        }
        else {
            $lines += ('F|{0}|{1}|{2}' -f ((Get-CodePointStrings -Text $name) -join ','), $null, [string]$entry.payloadSha256)
        }
    }

    return [pscustomobject]@{
        complete = $true
        entries = @($lines)
    }
}

function Test-C3InventoryMatchesSemantic {
    param(
        [Parameter(Mandatory = $true)]$Inventory,
        [Parameter(Mandatory = $true)]$FixtureCase
    )

    $expected = Get-C3ExpectedSemanticInventory -FixtureCase $FixtureCase
    if ($null -eq $expected) {
        return $null
    }

    $actual = @()
    foreach ($dir in @($Inventory.directories)) {
        $actual += ('D|{0}' -f (($dir.unicode.codePoints) -join ','))
    }
    foreach ($file in @($Inventory.files)) {
        $actual += ('F|{0}|{1}|{2}' -f (($file.unicode.codePoints) -join ','), $null, [string]$file.sha256)
    }

    $left = @($expected.entries | Sort-Object)
    $right = @($actual | Sort-Object)
    if ($left.Count -ne $right.Count) { return $false }
    for ($i = 0; $i -lt $left.Count; $i++) {
        if ([string]$left[$i] -cne [string]$right[$i]) { return $false }
    }
    return $true
}
