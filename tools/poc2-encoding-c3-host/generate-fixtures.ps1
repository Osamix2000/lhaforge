#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot '.baseline\poc2-encoding\c3-fixtures'
}

$psVersion = [version]$PSVersionTable.PSVersion
if (
    [string]$PSVersionTable.PSEdition -cne 'Desktop' -or
    $psVersion.Major -ne 5 -or
    $psVersion.Minor -ne 1
) {
    throw ('PoC 2-C3 host fixture generation requires Windows PowerShell 5.1 Desktop. Current runtime: {0} / {1}' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
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

function New-StringFromCodePoints {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    $builder = New-Object System.Text.StringBuilder
    foreach ($codePoint in $CodePoints) {
        if ($codePoint -lt 0 -or $codePoint -gt 0x10FFFF) {
            throw ('Invalid Unicode code point: 0x{0:X}' -f $codePoint)
        }
        if ($codePoint -ge 0xD800 -and $codePoint -le 0xDFFF) {
            throw ('Surrogate code point is not a scalar value: 0x{0:X}' -f $codePoint)
        }
        [void]$builder.Append([char]::ConvertFromUtf32($codePoint))
    }
    return $builder.ToString()
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

function Get-Le16 {
    param([Parameter(Mandatory = $true)][uint16]$Value)

    [byte[]]$bytes = [BitConverter]::GetBytes($Value)
    if (-not [BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }
    Write-Output -NoEnumerate $bytes
}

function Get-Le32 {
    param([Parameter(Mandatory = $true)][uint32]$Value)

    [byte[]]$bytes = [BitConverter]::GetBytes($Value)
    if (-not [BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }
    Write-Output -NoEnumerate $bytes
}

function Write-Bytes {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
    )

    if ($Bytes.Length -gt 0) {
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }
}

function Write-U16 {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][uint16]$Value
    )
    Write-Bytes -Stream $Stream -Bytes (Get-Le16 -Value $Value)
}

function Write-U32 {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][uint32]$Value
    )
    Write-Bytes -Stream $Stream -Bytes (Get-Le32 -Value $Value)
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

function Get-CodePointList {
    param([Parameter(Mandatory = $true)][string]$Text)

    $items = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $value = [int][char]$Text[$i]
        if ($value -ge 0xD800 -and $value -le 0xDBFF -and ($i + 1) -lt $Text.Length) {
            $next = [int][char]$Text[$i + 1]
            if ($next -ge 0xDC00 -and $next -le 0xDFFF) {
                $value = [char]::ConvertToUtf32($Text[$i], $Text[$i + 1])
                $i++
            }
        }
        [void]$items.Add(('U+{0:X4}' -f $value))
    }
    return @($items)
}

function Get-Utf8Bytes {
    param([Parameter(Mandatory = $true)][string]$Text)

    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [byte[]]$bytes = $encoding.GetBytes($Text)
    Write-Output -NoEnumerate $bytes
}

function Get-Cp932Bytes {
    param([Parameter(Mandatory = $true)][string]$Text)

    $encoderFallback = New-Object System.Text.EncoderExceptionFallback
    $decoderFallback = New-Object System.Text.DecoderExceptionFallback
    $encoding = [System.Text.Encoding]::GetEncoding(932, $encoderFallback, $decoderFallback)
    [byte[]]$bytes = $encoding.GetBytes($Text)
    Write-Output -NoEnumerate $bytes
}

function Join-ByteArrays {
    param([Parameter(Mandatory = $true)][object[]]$Arrays)

    $stream = New-Object System.IO.MemoryStream
    try {
        foreach ($item in $Arrays) {
            [byte[]]$bytes = $item
            Write-Bytes -Stream $stream -Bytes $bytes
        }
        [byte[]]$result = $stream.ToArray()
        Write-Output -NoEnumerate $result
    }
    finally {
        $stream.Dispose()
    }
}

function New-UnicodePathExtra {
    param(
        [Parameter(Mandatory = $true)][byte[]]$RawNameBytes,
        [Parameter(Mandatory = $true)][byte[]]$UnicodeNameBytes,
        [byte]$Version = 1,
        [object]$CrcOverride = $null
    )

    [uint32]$nameCrc = Get-Crc32 -Bytes $RawNameBytes
    if ($null -ne $CrcOverride) {
        $nameCrc = [uint32]$CrcOverride
    }

    [byte[]]$data = Join-ByteArrays -Arrays @(
        [byte[]]@($Version),
        (Get-Le32 -Value $nameCrc),
        $UnicodeNameBytes
    )

    [byte[]]$result = Join-ByteArrays -Arrays @(
        (Get-Le16 -Value 0x7075),
        (Get-Le16 -Value ([uint16]$data.Length)),
        $data
    )
    Write-Output -NoEnumerate $result
}

function New-Entry {
    param(
        [Parameter(Mandatory = $true)][byte[]]$NameBytes,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Data,
        [uint16]$Flags = 0,
        [AllowEmptyCollection()][byte[]]$ExtraBytes = [byte[]]@(),
        [uint32]$ExternalAttributes = 0,
        [string]$SemanticName = ''
    )

    return [pscustomobject]@{
        nameBytes = $NameBytes
        data = $Data
        flags = $Flags
        extraBytes = $ExtraBytes
        externalAttributes = $ExternalAttributes
        semanticName = $SemanticName
    }
}

function New-CasePayload {
    param([Parameter(Mandatory = $true)][string]$CaseId)
    $text = ('POC2-C3:{0}' -f $CaseId) + "`r`n"
    return ([System.Text.Encoding]::ASCII).GetBytes($text)
}

function Assert-Poc2C3EmptyByteArraySupport {
    [byte[]]$empty = [byte[]]@()

    if ((Get-Crc32 -Bytes $empty) -ne 0) {
        throw 'Empty payload CRC32 smoke test failed.'
    }
    if ((Get-Hex -Bytes $empty) -cne '') {
        throw 'Empty byte-array hex smoke test failed.'
    }
    if ((Get-Sha256Hex -Bytes $empty) -cne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
        throw 'Empty payload SHA-256 smoke test failed.'
    }

    $stream = New-Object System.IO.MemoryStream
    try {
        Write-Bytes -Stream $stream -Bytes $empty
        if ($stream.Length -ne 0) {
            throw 'Empty byte-array stream write smoke test failed.'
        }
    }
    finally {
        $stream.Dispose()
    }

    $entry = New-Entry -NameBytes (([Text.Encoding]::ASCII).GetBytes('__EMPTY__/')) -Data $empty -SemanticName '__EMPTY__/'
    if ($entry.data.Length -ne 0) {
        throw 'Empty entry payload smoke test failed.'
    }
}

function Get-Cases {
    $japaneseStem = New-StringFromCodePoints -CodePoints @(0x65E5, 0x672C, 0x8A9E)
    $japaneseName = $japaneseStem + '.txt'
    $alternateStem = New-StringFromCodePoints -CodePoints @(0x5225, 0x540D)
    $alternateName = $alternateStem + '.txt'
    $emojiName = 'emoji-' + (New-StringFromCodePoints -CodePoints @(0x1F600)) + '.txt'
    $nfcName = 'caf' + (New-StringFromCodePoints -CodePoints @(0x00E9)) + '.txt'
    $nfdName = 'cafe' + (New-StringFromCodePoints -CodePoints @(0x0301)) + '.txt'

    [byte[]]$japaneseUtf8 = Get-Utf8Bytes -Text $japaneseName
    [byte[]]$japaneseCp932 = Get-Cp932Bytes -Text $japaneseName
    [byte[]]$alternateUtf8 = Get-Utf8Bytes -Text $alternateName
    [byte[]]$invalidUtf8Name = [byte[]]@(0xE3, 0x28, 0xA1, 0x2E, 0x74, 0x78, 0x74)
    [byte[]]$ambiguousName = [byte[]]@(0xC2, 0xA9, 0x2E, 0x74, 0x78, 0x74)

    [uint32]$goodCrc = Get-Crc32 -Bytes $japaneseCp932
    [uint32]$badCrc = [uint32]($goodCrc -bxor 1)

    return @(
        [pscustomobject]@{
            id = 'ascii'
            behaviorClass = 'spec-valid'
            specNote = 'ASCII-only name, EFS clear.'
            entries = @(
                (New-Entry -NameBytes (([Text.Encoding]::ASCII).GetBytes('ascii.txt')) -Data (New-CasePayload -CaseId 'ascii') -SemanticName 'ascii.txt')
            )
        },
        [pscustomobject]@{
            id = 'utf8-japanese'
            behaviorClass = 'spec-valid'
            specNote = 'EFS bit 11 set; raw filename is strict UTF-8.'
            entries = @(
                (New-Entry -NameBytes $japaneseUtf8 -Flags 0x0800 -Data (New-CasePayload -CaseId 'utf8-japanese') -SemanticName $japaneseName)
            )
        },
        [pscustomobject]@{
            id = 'utf8-emoji'
            behaviorClass = 'spec-valid'
            specNote = 'EFS bit 11 set; supplementary-plane Unicode in UTF-8.'
            entries = @(
                (New-Entry -NameBytes (Get-Utf8Bytes -Text $emojiName) -Flags 0x0800 -Data (New-CasePayload -CaseId 'utf8-emoji') -SemanticName $emojiName)
            )
        },
        [pscustomobject]@{
            id = 'utf8-nfc'
            behaviorClass = 'spec-valid'
            specNote = 'EFS bit 11 set; NFC filename representation.'
            entries = @(
                (New-Entry -NameBytes (Get-Utf8Bytes -Text $nfcName) -Flags 0x0800 -Data (New-CasePayload -CaseId 'utf8-nfc') -SemanticName $nfcName)
            )
        },
        [pscustomobject]@{
            id = 'utf8-nfd'
            behaviorClass = 'spec-valid'
            specNote = 'EFS bit 11 set; NFD filename representation.'
            entries = @(
                (New-Entry -NameBytes (Get-Utf8Bytes -Text $nfdName) -Flags 0x0800 -Data (New-CasePayload -CaseId 'utf8-nfd') -SemanticName $nfdName)
            )
        },
        [pscustomobject]@{
            id = 'cp932-japanese'
            behaviorClass = 'legacy-observe'
            specNote = 'EFS clear; raw filename uses Windows CP932 as a legacy interoperability case.'
            entries = @(
                (New-Entry -NameBytes $japaneseCp932 -Data (New-CasePayload -CaseId 'cp932-japanese') -SemanticName $japaneseName)
            )
        },
        [pscustomobject]@{
            id = 'cp932-ambiguous'
            behaviorClass = 'legacy-observe'
            specNote = 'EFS clear; bytes C2 A9 are valid UTF-8 and also valid as two CP932 single-byte characters.'
            entries = @(
                (New-Entry -NameBytes $ambiguousName -Data (New-CasePayload -CaseId 'cp932-ambiguous'))
            )
        },
        [pscustomobject]@{
            id = 'cp932-upath-valid'
            behaviorClass = 'metadata-observe'
            specNote = 'EFS clear; CP932 raw name plus valid Info-ZIP Unicode Path extra field 0x7075.'
            entries = @(
                (New-Entry -NameBytes $japaneseCp932 -ExtraBytes (New-UnicodePathExtra -RawNameBytes $japaneseCp932 -UnicodeNameBytes $japaneseUtf8) -Data (New-CasePayload -CaseId 'cp932-upath-valid') -SemanticName $japaneseName)
            )
        },
        [pscustomobject]@{
            id = 'cp932-upath-bad-crc'
            behaviorClass = 'metadata-observe'
            specNote = '0x7075 NameCRC32 intentionally mismatches raw filename; APPNOTE says the extra field should be ignored.'
            entries = @(
                (New-Entry -NameBytes $japaneseCp932 -ExtraBytes (New-UnicodePathExtra -RawNameBytes $japaneseCp932 -UnicodeNameBytes $japaneseUtf8 -CrcOverride $badCrc) -Data (New-CasePayload -CaseId 'cp932-upath-bad-crc') -SemanticName $japaneseName)
            )
        },
        [pscustomobject]@{
            id = 'cp932-upath-conflict'
            behaviorClass = 'conflict-observe'
            specNote = 'Valid 0x7075 CRC but Unicode name intentionally conflicts with the legacy raw-name interpretation.'
            entries = @(
                (New-Entry -NameBytes $japaneseCp932 -ExtraBytes (New-UnicodePathExtra -RawNameBytes $japaneseCp932 -UnicodeNameBytes $alternateUtf8) -Data (New-CasePayload -CaseId 'cp932-upath-conflict'))
            )
        },
        [pscustomobject]@{
            id = 'utf8-upath-conflict'
            behaviorClass = 'conflict-observe'
            specNote = 'EFS bit 11 plus conflicting 0x7075; intentionally non-conformant precedence observation.'
            entries = @(
                (New-Entry -NameBytes $japaneseUtf8 -Flags 0x0800 -ExtraBytes (New-UnicodePathExtra -RawNameBytes $japaneseUtf8 -UnicodeNameBytes $alternateUtf8) -Data (New-CasePayload -CaseId 'utf8-upath-conflict'))
            )
        },
        [pscustomobject]@{
            id = 'invalid-utf8-flag'
            behaviorClass = 'malformed-observe'
            specNote = 'EFS bit 11 set while filename bytes are invalid UTF-8.'
            entries = @(
                (New-Entry -NameBytes $invalidUtf8Name -Flags 0x0800 -Data (New-CasePayload -CaseId 'invalid-utf8-flag'))
            )
        },
        [pscustomobject]@{
            id = 'upath-invalid-utf8'
            behaviorClass = 'malformed-observe'
            specNote = '0x7075 CRC is valid but UnicodeName payload is invalid UTF-8.'
            entries = @(
                (New-Entry -NameBytes $japaneseCp932 -ExtraBytes (New-UnicodePathExtra -RawNameBytes $japaneseCp932 -UnicodeNameBytes $invalidUtf8Name) -Data (New-CasePayload -CaseId 'upath-invalid-utf8'))
            )
        },
        [pscustomobject]@{
            id = 'upath-unknown-version'
            behaviorClass = 'malformed-observe'
            specNote = '0x7075 uses version 2; APPNOTE currently defines version 1 and says unknown versions should not be used.'
            entries = @(
                (New-Entry -NameBytes $japaneseCp932 -ExtraBytes (New-UnicodePathExtra -RawNameBytes $japaneseCp932 -UnicodeNameBytes $japaneseUtf8 -Version 2) -Data (New-CasePayload -CaseId 'upath-unknown-version'))
            )
        },
        [pscustomobject]@{
            id = 'macos-metadata'
            behaviorClass = 'cross-platform-observe'
            specNote = 'ASCII metadata names commonly present in macOS-created ZIPs; C3 observes rather than filters them.'
            entries = @(
                (New-Entry -NameBytes (([Text.Encoding]::ASCII).GetBytes('payload.txt')) -Data (([Text.Encoding]::ASCII).GetBytes("POC2-C3:macos:payload`r`n")) -SemanticName 'payload.txt'),
                (New-Entry -NameBytes (([Text.Encoding]::ASCII).GetBytes('.DS_Store')) -Data (([Text.Encoding]::ASCII).GetBytes("POC2-C3:macos:dsstore`r`n")) -SemanticName '.DS_Store'),
                (New-Entry -NameBytes (([Text.Encoding]::ASCII).GetBytes('__MACOSX/')) -Data ([byte[]]@()) -SemanticName '__MACOSX/'),
                (New-Entry -NameBytes (([Text.Encoding]::ASCII).GetBytes('__MACOSX/._payload.txt')) -Data (([Text.Encoding]::ASCII).GetBytes("POC2-C3:macos:appledouble`r`n")) -SemanticName '__MACOSX/._payload.txt')
            )
        }
    )
}

function Write-ZipFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Entries
    )

    $stream = New-Object System.IO.MemoryStream
    $centralRecords = New-Object System.Collections.ArrayList

    try {
        foreach ($entry in $Entries) {
            [uint32]$localOffset = [uint32]$stream.Position
            [uint32]$payloadCrc = Get-Crc32 -Bytes ([byte[]]$entry.data)
            [uint32]$payloadSize = [uint32]$entry.data.Length
            [uint16]$nameLength = [uint16]$entry.nameBytes.Length
            [uint16]$extraLength = [uint16]$entry.extraBytes.Length

            Write-U32 -Stream $stream -Value 0x04034B50
            Write-U16 -Stream $stream -Value 20
            Write-U16 -Stream $stream -Value ([uint16]$entry.flags)
            Write-U16 -Stream $stream -Value 0
            Write-U16 -Stream $stream -Value 0
            Write-U16 -Stream $stream -Value 0x0021
            Write-U32 -Stream $stream -Value $payloadCrc
            Write-U32 -Stream $stream -Value $payloadSize
            Write-U32 -Stream $stream -Value $payloadSize
            Write-U16 -Stream $stream -Value $nameLength
            Write-U16 -Stream $stream -Value $extraLength
            Write-Bytes -Stream $stream -Bytes ([byte[]]$entry.nameBytes)
            Write-Bytes -Stream $stream -Bytes ([byte[]]$entry.extraBytes)
            Write-Bytes -Stream $stream -Bytes ([byte[]]$entry.data)

            [void]$centralRecords.Add([pscustomobject]@{
                entry = $entry
                localOffset = $localOffset
                payloadCrc = $payloadCrc
                payloadSize = $payloadSize
            })
        }

        [uint32]$centralOffset = [uint32]$stream.Position

        foreach ($record in $centralRecords) {
            $entry = $record.entry
            [uint16]$nameLength = [uint16]$entry.nameBytes.Length
            [uint16]$extraLength = [uint16]$entry.extraBytes.Length

            Write-U32 -Stream $stream -Value 0x02014B50
            Write-U16 -Stream $stream -Value 20
            Write-U16 -Stream $stream -Value 20
            Write-U16 -Stream $stream -Value ([uint16]$entry.flags)
            Write-U16 -Stream $stream -Value 0
            Write-U16 -Stream $stream -Value 0
            Write-U16 -Stream $stream -Value 0x0021
            Write-U32 -Stream $stream -Value ([uint32]$record.payloadCrc)
            Write-U32 -Stream $stream -Value ([uint32]$record.payloadSize)
            Write-U32 -Stream $stream -Value ([uint32]$record.payloadSize)
            Write-U16 -Stream $stream -Value $nameLength
            Write-U16 -Stream $stream -Value $extraLength
            Write-U16 -Stream $stream -Value 0
            Write-U16 -Stream $stream -Value 0
            Write-U16 -Stream $stream -Value 0
            Write-U32 -Stream $stream -Value ([uint32]$entry.externalAttributes)
            Write-U32 -Stream $stream -Value ([uint32]$record.localOffset)
            Write-Bytes -Stream $stream -Bytes ([byte[]]$entry.nameBytes)
            Write-Bytes -Stream $stream -Bytes ([byte[]]$entry.extraBytes)
        }

        [uint32]$centralSize = [uint32]($stream.Position - $centralOffset)
        [uint16]$entryCount = [uint16]$centralRecords.Count

        Write-U32 -Stream $stream -Value 0x06054B50
        Write-U16 -Stream $stream -Value 0
        Write-U16 -Stream $stream -Value 0
        Write-U16 -Stream $stream -Value $entryCount
        Write-U16 -Stream $stream -Value $entryCount
        Write-U32 -Stream $stream -Value $centralSize
        Write-U32 -Stream $stream -Value $centralOffset
        Write-U16 -Stream $stream -Value 0

        [byte[]]$archiveBytes = $stream.ToArray()
        [System.IO.File]::WriteAllBytes($Path, $archiveBytes)
        Write-Output -NoEnumerate $archiveBytes
    }
    finally {
        $stream.Dispose()
    }
}

Assert-Poc2C3EmptyByteArraySupport
Write-Host '[POC2-C3] Empty byte-array PowerShell 5.1 smoke test passed.'

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$caseEvidence = New-Object System.Collections.ArrayList
foreach ($case in Get-Cases) {
    $archivePath = Join-Path $OutputRoot ($case.id + '.zip')
    [byte[]]$archiveBytes = Write-ZipFixture -Path $archivePath -Entries ([object[]]$case.entries)

    $entryEvidence = New-Object System.Collections.ArrayList
    foreach ($entry in $case.entries) {
        $semanticCodePoints = @()
        if (-not [string]::IsNullOrEmpty([string]$entry.semanticName)) {
            $semanticCodePoints = @(Get-CodePointList -Text ([string]$entry.semanticName))
        }

        [void]$entryEvidence.Add([pscustomobject]@{
            nameHex = Get-Hex -Bytes ([byte[]]$entry.nameBytes)
            flags = ('0x{0:X4}' -f [uint16]$entry.flags)
            efs = (([uint16]$entry.flags -band 0x0800) -ne 0)
            extraHex = Get-Hex -Bytes ([byte[]]$entry.extraBytes)
            payloadSha256 = Get-Sha256Hex -Bytes ([byte[]]$entry.data)
            semanticName = [string]$entry.semanticName
            semanticCodePoints = @($semanticCodePoints)
        })
    }

    [void]$caseEvidence.Add([pscustomobject]@{
        id = $case.id
        fileName = ($case.id + '.zip')
        behaviorClass = $case.behaviorClass
        specNote = $case.specNote
        sha256 = Get-Sha256Hex -Bytes $archiveBytes
        size = $archiveBytes.Length
        entryCount = $case.entries.Count
        entries = @($entryEvidence)
    })

    Write-Host ('[POC2-C3] Generated {0}  SHA-256={1}' -f ($case.id + '.zip'), (Get-Sha256Hex -Bytes $archiveBytes))
}

$manifest = [pscustomobject]@{
    schemaVersion = 1
    purpose = 'PoC 2-C3 deterministic raw ZIP metadata fixtures'
    generator = 'tools/poc2-encoding-c3-host/generate-fixtures.ps1'
    runtime = [pscustomobject]@{
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        psEdition = [string]$PSVersionTable.PSEdition
        defaultEncodingCodePage = [System.Text.Encoding]::Default.CodePage
        culture = [Globalization.CultureInfo]::CurrentCulture.Name
        uiCulture = [Globalization.CultureInfo]::CurrentUICulture.Name
    }
    zipProfile = [pscustomobject]@{
        compressionMethod = 'Store'
        versionNeeded = 20
        versionMadeBy = 20
        dosTime = '0x0000'
        dosDate = '0x0021'
        dataDescriptor = $false
        archiveComment = $false
    }
    cases = @($caseEvidence)
}

$manifestPath = Join-Path $OutputRoot 'fixture-manifest.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8NoBom)

Write-Host ''
Write-Host ('[POC2-C3] Output: {0}' -f $OutputRoot)
Write-Host ('[POC2-C3] Cases: {0}' -f $caseEvidence.Count)
Write-Host '[POC2-C3] Run validate-fixtures.ps1 next.'
