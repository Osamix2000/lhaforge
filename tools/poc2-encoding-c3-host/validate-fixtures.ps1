#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$FixtureRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($FixtureRoot)) {
    $FixtureRoot = Join-Path $repoRoot '.baseline\poc2-encoding\c3-fixtures'
}

$psVersion = [version]$PSVersionTable.PSVersion
if (
    [string]$PSVersionTable.PSEdition -cne 'Desktop' -or
    $psVersion.Major -ne 5 -or
    $psVersion.Minor -ne 1
) {
    throw ('PoC 2-C3 host fixture validation requires Windows PowerShell 5.1 Desktop. Current runtime: {0} / {1}' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
}

$script:Crc32Table = [uint32[]]@(
    0, 1996959894, 3993919788, 2567524794, 124634137, 1886057615, 3915621685, 2657392035,
    249268274, 2044508324, 3772115230, 2547177864, 162941995, 2125561021, 3887607047, 2428444049,
    498536548, 1789927666, 4089016648, 2227061214, 450548861, 1843258603, 4107580753, 2211677639,
    325883990, 1684777152, 4251122042, 2321926636, 335633487, 1661365465, 4195302755, 2366115317,
    997073096, 1281953886, 3579855332, 2724688242, 1006888145, 1258607687, 3524101629, 2768942443,
    901097722, 1119000684, 3686517206, 2898065728, 853044451, 1172266101, 3705015759, 2882616665,
    651767980, 1373503546, 3369554304, 3218104598, 565507253, 1454621731, 3485111705, 3099436303,
    671266974, 1594198024, 3322730930, 2970347812, 795835527, 1483230225, 3244367275, 3060149565,
    1994146192, 31158534, 2563907772, 4023717930, 1907459465, 112637215, 2680153253, 3904427059,
    2013776290, 251722036, 2517215374, 3775830040, 2137656763, 141376813, 2439277719, 3865271297,
    1802195444, 476864866, 2238001368, 4066508878, 1812370925, 453092731, 2181625025, 4111451223,
    1706088902, 314042704, 2344532202, 4240017532, 1658658271, 366619977, 2362670323, 4224994405,
    1303535960, 984961486, 2747007092, 3569037538, 1256170817, 1037604311, 2765210733, 3554079995,
    1131014506, 879679996, 2909243462, 3663771856, 1141124467, 855842277, 2852801631, 3708648649,
    1342533948, 654459306, 3188396048, 3373015174, 1466479909, 544179635, 3110523913, 3462522015,
    1591671054, 702138776, 2966460450, 3352799412, 1504918807, 783551873, 3082640443, 3233442989,
    3988292384, 2596254646, 62317068, 1957810842, 3939845945, 2647816111, 81470997, 1943803523,
    3814918930, 2489596804, 225274430, 2053790376, 3826175755, 2466906013, 167816743, 2097651377,
    4027552580, 2265490386, 503444072, 1762050814, 4150417245, 2154129355, 426522225, 1852507879,
    4275313526, 2312317920, 282753626, 1742555852, 4189708143, 2394877945, 397917763, 1622183637,
    3604390888, 2714866558, 953729732, 1340076626, 3518719985, 2797360999, 1068828381, 1219638859,
    3624741850, 2936675148, 906185462, 1090812512, 3747672003, 2825379669, 829329135, 1181335161,
    3412177804, 3160834842, 628085408, 1382605366, 3423369109, 3138078467, 570562233, 1426400815,
    3317316542, 2998733608, 733239954, 1555261956, 3268935591, 3050360625, 752459403, 1541320221,
    2607071920, 3965973030, 1969922972, 40735498, 2617837225, 3943577151, 1913087877, 83908371,
    2512341634, 3803740692, 2075208622, 213261112, 2463272603, 3855990285, 2094854071, 198958881,
    2262029012, 4057260610, 1759359992, 534414190, 2176718541, 4139329115, 1873836001, 414664567,
    2282248934, 4279200368, 1711684554, 285281116, 2405801727, 4167216745, 1634467795, 376229701,
    2685067896, 3608007406, 1308918612, 956543938, 2808555105, 3495958263, 1231636301, 1047427035,
    2932959818, 3654703836, 1088359270, 936918000, 2847714899, 3736837829, 1202900863, 817233897,
    3183342108, 3401237130, 1404277552, 615818150, 3134207493, 3453421203, 1423857449, 601450431,
    3009837614, 3294710456, 1567103746, 711928724, 3020668471, 3272380065, 1510334235, 755167117
)

$script:Expected = @{
    'ascii' = [pscustomobject]@{
        sha256 = 'ce18a398ab39e50f4215c76132602888b59612be150c5c1f46cd2316ef161e2a'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '61736369692E747874'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = '21f39a981f4348aa1dfb63d2c559b3beb935e631eb067313dd6a817073c5ffc0' }
        )
    }
    'utf8-japanese' = [pscustomobject]@{
        sha256 = '3157c1131c0bb9fd09802e3716a6892482101f133b089717c1731e4a48bfb12b'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = 'E697A5E69CACE8AA9E2E747874'; flags = 2048; extraHex = ''; externalAttributes = 0; payloadSha256 = '16695611a0cd79bdac01c059d850fde67dbfbd4ad4881dd585a4b0b9d8cc132b' }
        )
    }
    'utf8-emoji' = [pscustomobject]@{
        sha256 = '2917aeef94e2f0b130fc9978fc55968643243c1857c338aec700d641905b5298'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '656D6F6A692DF09F98802E747874'; flags = 2048; extraHex = ''; externalAttributes = 0; payloadSha256 = '5d559be8f2e25b80dfd8b68c1b92108e36c82397af26e6c0a5c52f3f79f98768' }
        )
    }
    'utf8-nfc' = [pscustomobject]@{
        sha256 = '0c5523eda6b603eaa0c19d5a55e78a6255e045a4e96d4915639d8c535c95b51d'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '636166C3A92E747874'; flags = 2048; extraHex = ''; externalAttributes = 0; payloadSha256 = '9304903a916630cfd80f927b5d0a6baddf9134b3b3bf11462e031d7c7ee53d5c' }
        )
    }
    'utf8-nfd' = [pscustomobject]@{
        sha256 = '7604c32e7c24626a65df4fcfcc48ceddd8c68cca08009bcc2f632f4e9fbd77cd'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '63616665CC812E747874'; flags = 2048; extraHex = ''; externalAttributes = 0; payloadSha256 = 'af4b6ea75456796d2b25470017d228c0a21269df3bf008ea8d9e70af593c75ed' }
        )
    }
    'cp932-japanese' = [pscustomobject]@{
        sha256 = 'a3937ae3d1ce93464f754e788187f5c7727e47cb8e542695e9735f8fa4bfabe4'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '93FA967B8CEA2E747874'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = 'b3f22c2badc16759f62d1744770abaf8aeacfb7352560299b337a07e880b7631' }
        )
    }
    'cp932-ambiguous' = [pscustomobject]@{
        sha256 = 'b70295e558d4e32c8c6afeb24a89c1ade8753b85b69b3b605df44c7bcc113a9b'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = 'C2A92E747874'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = '11372dfced251b5d54f94b95b12411f5e77058640cf92c553e9f40853c4b62ff' }
        )
    }
    'cp932-upath-valid' = [pscustomobject]@{
        sha256 = 'ce769489ef71130a0ee1a9893b51e768825f235f6b396684f9b87bce2bd9667c'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '93FA967B8CEA2E747874'; flags = 0; extraHex = '7570120001B87EC365E697A5E69CACE8AA9E2E747874'; externalAttributes = 0; payloadSha256 = 'caa4431ab3f44b0e1a4f5e255da96c6e851e14661de1adf76fb1fb9d79dfd23f' }
        )
    }
    'cp932-upath-bad-crc' = [pscustomobject]@{
        sha256 = '4590a945bc06557628ecea0a1b28d18ea69645a263ff6de22ca7d57f6232f456'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '93FA967B8CEA2E747874'; flags = 0; extraHex = '7570120001B97EC365E697A5E69CACE8AA9E2E747874'; externalAttributes = 0; payloadSha256 = 'd96d43a3d556aea04b1632c106f11064dd1524eb15928b309aaf0cf90f4adcc6' }
        )
    }
    'cp932-upath-conflict' = [pscustomobject]@{
        sha256 = 'f02a51af7bc966d503355479cabd1a5ed32956fd4c4b72039ff7f40b7f7357a9'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '93FA967B8CEA2E747874'; flags = 0; extraHex = '75700F0001B87EC365E588A5E5908D2E747874'; externalAttributes = 0; payloadSha256 = '16e7d837243795039c3fefd363e3de1029fa3926e5a89eb92c705ab3c463bbaa' }
        )
    }
    'utf8-upath-conflict' = [pscustomobject]@{
        sha256 = 'ef9d577380b5eda37a76a1cf4712311a68323f13971b89b111676ed2066fc93b'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = 'E697A5E69CACE8AA9E2E747874'; flags = 2048; extraHex = '75700F00018338BF37E588A5E5908D2E747874'; externalAttributes = 0; payloadSha256 = 'fb2acc331717e057664436f9906215a069558593d316e5c17686fc7be9f226b3' }
        )
    }
    'invalid-utf8-flag' = [pscustomobject]@{
        sha256 = 'f5a66a68d901a9f0c98f16aecd3df696cebd1f2009aaa04b02fff5394f69dcb8'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = 'E328A12E747874'; flags = 2048; extraHex = ''; externalAttributes = 0; payloadSha256 = 'c936408796f1a7d71576b163563f77528a3dc0985f099b847b26a201909b6d8b' }
        )
    }
    'upath-invalid-utf8' = [pscustomobject]@{
        sha256 = '8717cbc1e393b46638cd5d6a8728e654b7d0c4d912004ea12229641aa4e21bcb'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '93FA967B8CEA2E747874'; flags = 0; extraHex = '75700C0001B87EC365E328A12E747874'; externalAttributes = 0; payloadSha256 = 'f05328d274fb47a38f9791a6c776b0e9be22de391e766b108870b835cddd173c' }
        )
    }
    'upath-unknown-version' = [pscustomobject]@{
        sha256 = '4f34cccf47f14a653dece50e0b4591f73e46d4b8b417a604048631a5f78aa211'
        entryCount = 1
        entries = @(
            [pscustomobject]@{ nameHex = '93FA967B8CEA2E747874'; flags = 0; extraHex = '7570120002B87EC365E697A5E69CACE8AA9E2E747874'; externalAttributes = 0; payloadSha256 = '45a150268e9abfeac88f984fe8f1cb439a6b7a558befe4aad90ee4b16a0e5122' }
        )
    }
    'macos-metadata' = [pscustomobject]@{
        sha256 = '0668be22ca3671dc21bba6e69be000b024727eff156324a109ae18fe59ec0021'
        entryCount = 4
        entries = @(
            [pscustomobject]@{ nameHex = '7061796C6F61642E747874'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = '84c2a55e0f8977237ed00b46e8fabe4648a93cbc0bac53662eadb91b057730b9' },
            [pscustomobject]@{ nameHex = '2E44535F53746F7265'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = 'abda16f3c6952c65863684c2a450296c35fea0091f829dd40eae1cdf5de0aca1' },
            [pscustomobject]@{ nameHex = '5F5F4D41434F53582F'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' },
            [pscustomobject]@{ nameHex = '5F5F4D41434F53582F2E5F7061796C6F61642E747874'; flags = 0; extraHex = ''; externalAttributes = 0; payloadSha256 = '99e4d6a042e4069a82990b49073818ce6e6c23be0eb581febec248d17ea7e6eb' }
        )
    }
}

function Get-Hex {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    return [BitConverter]::ToString($Bytes).Replace('-', '')
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (Get-Hex -Bytes $sha.ComputeHash($Bytes)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Crc32 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    [uint32]$crc = [uint32]::MaxValue
    foreach ($b in $Bytes) {
        $index = [int](($crc -bxor [uint32]$b) -band 0xFF)
        $crc = [uint32](($crc -shr 8) -bxor $script:Crc32Table[$index])
    }
    return [uint32]($crc -bxor [uint32]::MaxValue)
}

function Read-U16 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset
    )
    if ($Offset -lt 0 -or ($Offset + 2) -gt $Bytes.Length) {
        throw ('Read-U16 out of range at offset {0}.' -f $Offset)
    }
    if ([BitConverter]::IsLittleEndian) {
        return [BitConverter]::ToUInt16($Bytes, $Offset)
    }
    [byte[]]$temp = $Bytes[$Offset..($Offset + 1)]
    [Array]::Reverse($temp)
    return [BitConverter]::ToUInt16($temp, 0)
}

function Read-U32 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset
    )
    if ($Offset -lt 0 -or ($Offset + 4) -gt $Bytes.Length) {
        throw ('Read-U32 out of range at offset {0}.' -f $Offset)
    }
    if ([BitConverter]::IsLittleEndian) {
        return [BitConverter]::ToUInt32($Bytes, $Offset)
    }
    [byte[]]$temp = $Bytes[$Offset..($Offset + 3)]
    [Array]::Reverse($temp)
    return [BitConverter]::ToUInt32($temp, 0)
}

function Get-Slice {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset,
        [Parameter(Mandatory = $true)][int]$Length
    )
    if ($Length -lt 0 -or $Offset -lt 0 -or ($Offset + $Length) -gt $Bytes.Length) {
        throw ('Slice out of range: offset={0}, length={1}, total={2}.' -f $Offset, $Length, $Bytes.Length)
    }
    if ($Length -eq 0) {
        Write-Output -NoEnumerate ([byte[]]@())
        return
    }
    [byte[]]$result = $Bytes[$Offset..($Offset + $Length - 1)]
    Write-Output -NoEnumerate $result
}

function Find-EocdOffset {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $minimum = [Math]::Max(0, $Bytes.Length - 65557)
    for ($offset = $Bytes.Length - 22; $offset -ge $minimum; $offset--) {
        if (
            $Bytes[$offset] -eq 0x50 -and
            $Bytes[$offset + 1] -eq 0x4B -and
            $Bytes[$offset + 2] -eq 0x05 -and
            $Bytes[$offset + 3] -eq 0x06
        ) {
            [uint16]$commentLength = Read-U16 -Bytes $Bytes -Offset ($offset + 20)
            if (($offset + 22 + $commentLength) -eq $Bytes.Length) {
                return $offset
            }
        }
    }
    throw 'EOCD signature not found.'
}

function Parse-ExtraFields {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ExtraBytes)

    $blocks = New-Object System.Collections.ArrayList
    $offset = 0
    while ($offset -lt $ExtraBytes.Length) {
        if (($offset + 4) -gt $ExtraBytes.Length) {
            throw ('Truncated extra field header at offset {0}.' -f $offset)
        }
        [uint16]$id = Read-U16 -Bytes $ExtraBytes -Offset $offset
        [uint16]$size = Read-U16 -Bytes $ExtraBytes -Offset ($offset + 2)
        $dataOffset = $offset + 4
        if (($dataOffset + $size) -gt $ExtraBytes.Length) {
            throw ('Truncated extra field data for id 0x{0:X4}.' -f $id)
        }
        [byte[]]$data = Get-Slice -Bytes $ExtraBytes -Offset $dataOffset -Length $size
        [void]$blocks.Add([pscustomobject]@{
            id = $id
            size = $size
            data = $data
        })
        $offset = $dataOffset + $size
    }
    return @($blocks)
}

function Test-StrictUtf8 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        [void]$encoding.GetString($Bytes)
        return $true
    }
    catch [System.Text.DecoderFallbackException] {
        return $false
    }
}

function Parse-ZipFixture {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $eocd = Find-EocdOffset -Bytes $Bytes
    if ((Read-U32 -Bytes $Bytes -Offset $eocd) -ne 0x06054B50) {
        throw 'Invalid EOCD signature.'
    }

    [uint16]$disk = Read-U16 -Bytes $Bytes -Offset ($eocd + 4)
    [uint16]$centralDisk = Read-U16 -Bytes $Bytes -Offset ($eocd + 6)
    [uint16]$entriesOnDisk = Read-U16 -Bytes $Bytes -Offset ($eocd + 8)
    [uint16]$entryCount = Read-U16 -Bytes $Bytes -Offset ($eocd + 10)
    [uint32]$centralSize = Read-U32 -Bytes $Bytes -Offset ($eocd + 12)
    [uint32]$centralOffset = Read-U32 -Bytes $Bytes -Offset ($eocd + 16)
    [uint16]$commentLength = Read-U16 -Bytes $Bytes -Offset ($eocd + 20)

    if ($disk -ne 0 -or $centralDisk -ne 0) {
        throw 'Multi-disk ZIP is outside the C3 fixture profile.'
    }
    if ($entriesOnDisk -ne $entryCount) {
        throw 'EOCD entry count mismatch.'
    }
    if ($commentLength -ne 0) {
        throw 'Archive comment is outside the C3 fixture profile.'
    }
    if (($centralOffset + $centralSize) -ne $eocd) {
        throw 'Central directory extent does not end at EOCD.'
    }

    $entries = New-Object System.Collections.ArrayList
    $offset = [int]$centralOffset

    for ($index = 0; $index -lt $entryCount; $index++) {
        if ((Read-U32 -Bytes $Bytes -Offset $offset) -ne 0x02014B50) {
            throw ('Invalid central directory signature for entry {0} at offset {1}.' -f $index, $offset)
        }

        [uint16]$madeBy = Read-U16 -Bytes $Bytes -Offset ($offset + 4)
        [uint16]$versionNeeded = Read-U16 -Bytes $Bytes -Offset ($offset + 6)
        [uint16]$flags = Read-U16 -Bytes $Bytes -Offset ($offset + 8)
        [uint16]$method = Read-U16 -Bytes $Bytes -Offset ($offset + 10)
        [uint16]$dosTime = Read-U16 -Bytes $Bytes -Offset ($offset + 12)
        [uint16]$dosDate = Read-U16 -Bytes $Bytes -Offset ($offset + 14)
        [uint32]$crc = Read-U32 -Bytes $Bytes -Offset ($offset + 16)
        [uint32]$compressedSize = Read-U32 -Bytes $Bytes -Offset ($offset + 20)
        [uint32]$uncompressedSize = Read-U32 -Bytes $Bytes -Offset ($offset + 24)
        [uint16]$nameLength = Read-U16 -Bytes $Bytes -Offset ($offset + 28)
        [uint16]$extraLength = Read-U16 -Bytes $Bytes -Offset ($offset + 30)
        [uint16]$fileCommentLength = Read-U16 -Bytes $Bytes -Offset ($offset + 32)
        [uint16]$diskStart = Read-U16 -Bytes $Bytes -Offset ($offset + 34)
        [uint16]$internalAttributes = Read-U16 -Bytes $Bytes -Offset ($offset + 36)
        [uint32]$externalAttributes = Read-U32 -Bytes $Bytes -Offset ($offset + 38)
        [uint32]$localOffset = Read-U32 -Bytes $Bytes -Offset ($offset + 42)

        $cursor = $offset + 46
        [byte[]]$nameBytes = Get-Slice -Bytes $Bytes -Offset $cursor -Length $nameLength
        $cursor += $nameLength
        [byte[]]$extraBytes = Get-Slice -Bytes $Bytes -Offset $cursor -Length $extraLength
        $cursor += $extraLength
        [byte[]]$commentBytes = Get-Slice -Bytes $Bytes -Offset $cursor -Length $fileCommentLength
        $cursor += $fileCommentLength

        if ($madeBy -ne 20 -or $versionNeeded -ne 20) {
            throw ('Unexpected ZIP version fields for entry {0}.' -f $index)
        }
        if ($method -ne 0) {
            throw ('C3 fixtures must use Store method; entry {0} uses {1}.' -f $index, $method)
        }
        if ($dosTime -ne 0 -or $dosDate -ne 0x0021) {
            throw ('Unexpected timestamp fields for entry {0}.' -f $index)
        }
        if ($compressedSize -ne $uncompressedSize) {
            throw ('Stored entry size mismatch for entry {0}.' -f $index)
        }
        if ($fileCommentLength -ne 0 -or $commentBytes.Length -ne 0) {
            throw ('Entry comment is outside the C3 fixture profile.')
        }
        if ($diskStart -ne 0 -or $internalAttributes -ne 0) {
            throw ('Unexpected central metadata for entry {0}.' -f $index)
        }

        if ((Read-U32 -Bytes $Bytes -Offset ([int]$localOffset)) -ne 0x04034B50) {
            throw ('Invalid local header signature for entry {0}.' -f $index)
        }

        [uint16]$localVersion = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 4)
        [uint16]$localFlags = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 6)
        [uint16]$localMethod = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 8)
        [uint16]$localTime = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 10)
        [uint16]$localDate = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 12)
        [uint32]$localCrc = Read-U32 -Bytes $Bytes -Offset ([int]$localOffset + 14)
        [uint32]$localCompressedSize = Read-U32 -Bytes $Bytes -Offset ([int]$localOffset + 18)
        [uint32]$localUncompressedSize = Read-U32 -Bytes $Bytes -Offset ([int]$localOffset + 22)
        [uint16]$localNameLength = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 26)
        [uint16]$localExtraLength = Read-U16 -Bytes $Bytes -Offset ([int]$localOffset + 28)

        $localCursor = [int]$localOffset + 30
        [byte[]]$localName = Get-Slice -Bytes $Bytes -Offset $localCursor -Length $localNameLength
        $localCursor += $localNameLength
        [byte[]]$localExtra = Get-Slice -Bytes $Bytes -Offset $localCursor -Length $localExtraLength
        $localCursor += $localExtraLength
        [byte[]]$payload = Get-Slice -Bytes $Bytes -Offset $localCursor -Length ([int]$localCompressedSize)

        if (
            $localVersion -ne $versionNeeded -or
            $localFlags -ne $flags -or
            $localMethod -ne $method -or
            $localTime -ne $dosTime -or
            $localDate -ne $dosDate -or
            $localCrc -ne $crc -or
            $localCompressedSize -ne $compressedSize -or
            $localUncompressedSize -ne $uncompressedSize
        ) {
            throw ('Local/central fixed-field mismatch for entry {0}.' -f $index)
        }

        if ((Get-Hex -Bytes $localName) -cne (Get-Hex -Bytes $nameBytes)) {
            throw ('Local/central filename mismatch for entry {0}.' -f $index)
        }
        if ((Get-Hex -Bytes $localExtra) -cne (Get-Hex -Bytes $extraBytes)) {
            throw ('Local/central extra field mismatch for entry {0}.' -f $index)
        }
        if ((Get-Crc32 -Bytes $payload) -ne $crc) {
            throw ('Payload CRC mismatch for entry {0}.' -f $index)
        }

        $extraBlocks = @(Parse-ExtraFields -ExtraBytes $extraBytes)

        [void]$entries.Add([pscustomobject]@{
            index = $index
            flags = $flags
            nameBytes = $nameBytes
            extraBytes = $extraBytes
            extraBlocks = @($extraBlocks)
            payload = $payload
            externalAttributes = $externalAttributes
        })

        $offset = $cursor
    }

    if ($offset -ne $eocd) {
        throw ('Central directory parsed length mismatch: parsed end={0}, EOCD={1}.' -f $offset, $eocd)
    }

    return [pscustomobject]@{
        entryCount = [int]$entryCount
        entries = @($entries)
        centralOffset = [uint32]$centralOffset
        centralSize = [uint32]$centralSize
        eocdOffset = [int]$eocd
    }
}

function Assert-UpathInternalConsistency {
    param(
        [Parameter(Mandatory = $true)][byte[]]$NameBytes,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ExtraBlocks,
        [Parameter(Mandatory = $true)][string]$CaseId
    )

    $upath = @($ExtraBlocks | Where-Object { $_.id -eq 0x7075 })
    if ($upath.Count -eq 0) {
        return
    }
    if ($upath.Count -ne 1) {
        throw ('{0}: expected at most one 0x7075 field, got {1}.' -f $CaseId, $upath.Count)
    }

    [byte[]]$data = $upath[0].data
    if ($data.Length -lt 5) {
        throw ('{0}: 0x7075 data shorter than Version + NameCRC32.' -f $CaseId)
    }

    [byte]$version = $data[0]
    [uint32]$storedNameCrc = Read-U32 -Bytes $data -Offset 1
    [uint32]$actualNameCrc = Get-Crc32 -Bytes $NameBytes
    [byte[]]$unicodeBytes = Get-Slice -Bytes $data -Offset 5 -Length ($data.Length - 5)

    $strictUtf8 = Test-StrictUtf8 -Bytes $unicodeBytes
    Write-Host ('    0x7075 version={0}, nameCrcMatch={1}, unicodeUtf8Valid={2}' -f $version, ($storedNameCrc -eq $actualNameCrc), $strictUtf8)
}

function Assert-Poc2C3EmptyByteArrayValidationSupport {
    [byte[]]$empty = [byte[]]@()

    if ((Get-Crc32 -Bytes $empty) -ne 0) {
        throw 'Validator empty payload CRC32 smoke test failed.'
    }
    if ((Get-Hex -Bytes $empty) -cne '') {
        throw 'Validator empty byte-array hex smoke test failed.'
    }
    if ((Get-Sha256Hex -Bytes $empty) -cne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
        throw 'Validator empty payload SHA-256 smoke test failed.'
    }
    if ((@(Parse-ExtraFields -ExtraBytes $empty)).Count -ne 0) {
        throw 'Validator empty extra-field parse smoke test failed.'
    }
    if (-not (Test-StrictUtf8 -Bytes $empty)) {
        throw 'Validator empty UTF-8 buffer smoke test failed.'
    }

    Assert-UpathInternalConsistency -NameBytes (([Text.Encoding]::ASCII).GetBytes('empty.txt')) -ExtraBlocks ([object[]]@()) -CaseId 'empty-smoke-test'
}

Assert-Poc2C3EmptyByteArrayValidationSupport
Write-Host '[POC2-C3] Validator empty byte-array PowerShell 5.1 smoke test passed.'

if (-not (Test-Path -LiteralPath $FixtureRoot -PathType Container)) {
    throw ('Fixture root does not exist: {0}' -f $FixtureRoot)
}

$issues = New-Object System.Collections.ArrayList
$caseIds = @($script:Expected.Keys | Sort-Object)

foreach ($caseId in $caseIds) {
    try {
        $expectedCase = $script:Expected[$caseId]
        $path = Join-Path $FixtureRoot ($caseId + '.zip')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ('Missing fixture: {0}' -f $path)
        }

        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($path)
        $actualSha = Get-Sha256Hex -Bytes $bytes
        if ($actualSha -cne [string]$expectedCase.sha256) {
            throw ('SHA-256 mismatch. Expected {0}, got {1}.' -f $expectedCase.sha256, $actualSha)
        }

        $parsed = Parse-ZipFixture -Bytes $bytes
        if ($parsed.entryCount -ne [int]$expectedCase.entryCount) {
            throw ('Entry count mismatch. Expected {0}, got {1}.' -f $expectedCase.entryCount, $parsed.entryCount)
        }

        for ($i = 0; $i -lt $parsed.entryCount; $i++) {
            $actualEntry = $parsed.entries[$i]
            $expectedEntry = $expectedCase.entries[$i]

            $actualNameHex = Get-Hex -Bytes ([byte[]]$actualEntry.nameBytes)
            $actualExtraHex = Get-Hex -Bytes ([byte[]]$actualEntry.extraBytes)
            $actualPayloadSha = Get-Sha256Hex -Bytes ([byte[]]$actualEntry.payload)

            if ($actualNameHex -cne [string]$expectedEntry.nameHex) {
                throw ('Entry {0} raw filename mismatch. Expected {1}, got {2}.' -f $i, $expectedEntry.nameHex, $actualNameHex)
            }
            if ([uint16]$actualEntry.flags -ne [uint16]$expectedEntry.flags) {
                throw ('Entry {0} flags mismatch. Expected 0x{1:X4}, got 0x{2:X4}.' -f $i, [uint16]$expectedEntry.flags, [uint16]$actualEntry.flags)
            }
            if ($actualExtraHex -cne [string]$expectedEntry.extraHex) {
                throw ('Entry {0} extra field mismatch. Expected {1}, got {2}.' -f $i, $expectedEntry.extraHex, $actualExtraHex)
            }
            if ([uint32]$actualEntry.externalAttributes -ne [uint32]$expectedEntry.externalAttributes) {
                throw ('Entry {0} external attributes mismatch.' -f $i)
            }
            if ($actualPayloadSha -cne [string]$expectedEntry.payloadSha256) {
                throw ('Entry {0} payload SHA-256 mismatch.' -f $i)
            }

            if (([uint16]$actualEntry.flags -band 0x0800) -ne 0) {
                $isValidUtf8 = Test-StrictUtf8 -Bytes ([byte[]]$actualEntry.nameBytes)
                Write-Host ('    EFS filename strict UTF-8 valid={0}' -f $isValidUtf8)
            }

            Assert-UpathInternalConsistency -NameBytes ([byte[]]$actualEntry.nameBytes) -ExtraBlocks ([object[]]$actualEntry.extraBlocks) -CaseId $caseId
        }

        Write-Host ('[PASS] {0}  SHA-256={1}' -f $caseId, $actualSha)
    }
    catch {
        [void]$issues.Add([pscustomobject]@{
            caseId = $caseId
            error = $_.Exception.Message
        })
        Write-Host ('[FAIL] {0}: {1}' -f $caseId, $_.Exception.Message)
    }
}

$unexpected = @(Get-ChildItem -LiteralPath $FixtureRoot -Filter '*.zip' -File | Where-Object {
    $script:Expected.ContainsKey($_.BaseName) -eq $false
})
foreach ($file in $unexpected) {
    [void]$issues.Add([pscustomobject]@{
        caseId = $file.BaseName
        error = 'Unexpected ZIP fixture file.'
    })
    Write-Host ('[FAIL] Unexpected ZIP fixture: {0}' -f $file.Name)
}

Write-Host ''
if ($issues.Count -gt 0) {
    Write-Host ('[POC2-C3] Validation FAILED with {0} issue(s).' -f $issues.Count)
    foreach ($issue in $issues) {
        Write-Host ('  {0}: {1}' -f $issue.caseId, $issue.error)
    }
    exit 1
}

Write-Host ('[POC2-C3] Validation PASS. Cases={0}' -f $caseIds.Count)
Write-Host ('[POC2-C3] Fixture root: {0}' -f $FixtureRoot)
