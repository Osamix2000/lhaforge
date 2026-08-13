Set-StrictMode -Version 2.0

function Write-JsonUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 16
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json + "`n", $encoding)
}

function Read-JsonUtf8 {
	param(
		[Parameter(Mandatory = $true)][string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw ('JSON file was not found: {0}' -f $Path)
	}

	$encoding = New-Object System.Text.UTF8Encoding($false, $true)
	$json = [System.IO.File]::ReadAllText($Path, $encoding)
	return ($json | ConvertFrom-Json)
}

function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

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
            if ($reader.ReadUInt16() -ne 0x5A4D) { throw ('Not a PE image: {0}' -f $Path) }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
                throw ('Invalid PE header offset: {0}' -f $Path)
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) { throw ('Missing PE signature: {0}' -f $Path) }
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

function Get-FileHashEvidence {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
            sizeBytes = $null
            sha256 = $null
        }
    }

    $file = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        path = $file.FullName
        exists = $true
        sizeBytes = [Int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
    return [pscustomobject]@{
        path = $file.FullName
        sizeBytes = [Int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        peMachine = ('0x{0:x4}' -f $machine)
        architecture = if ($machine -eq 0x014C) { 'x86' } else { 'other' }
        fileVersion = [string]$version.FileVersion
        productVersion = [string]$version.ProductVersion
    }
}

function New-StringFromCodePoints {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    $builder = New-Object System.Text.StringBuilder
    foreach ($cp in $CodePoints) {
        if ($cp -lt 0 -or $cp -gt 0x10FFFF) {
            throw ('Invalid Unicode code point: {0}' -f $cp)
        }
        [void]$builder.Append([char]::ConvertFromUtf32($cp))
    }
    return $builder.ToString()
}

function Get-CodePointStrings {
    param([Parameter(Mandatory = $true)][string]$Text)

    $result = @()
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = [char]$Text[$i]
        if ([char]::IsHighSurrogate($ch)) {
            if (($i + 1) -ge $Text.Length -or -not [char]::IsLowSurrogate([char]$Text[$i + 1])) {
                $result += ('U+{0:X4}' -f [int]$ch)
                $i++
                continue
            }
            $cp = [char]::ConvertToUtf32($ch, [char]$Text[$i + 1])
            $result += ('U+{0:X6}' -f $cp)
            $i += 2
            continue
        }

        $result += ('U+{0:X4}' -f [int]$ch)
        $i++
    }
    return @($result)
}

function Get-UnicodeStringEvidence {
    param([Parameter(Mandatory = $true)][string]$Text)

    return [pscustomobject]@{
        text = $Text
        codePoints = @(Get-CodePointStrings -Text $Text)
        utf8Sha256 = Get-StringSha256 -Text $Text
        isNfc = ($Text -ceq $Text.Normalize([System.Text.NormalizationForm]::FormC))
        isNfd = ($Text -ceq $Text.Normalize([System.Text.NormalizationForm]::FormD))
    }
}

function Get-Poc2C1Cases {
    return @(
        [pscustomobject]@{ id = 'ascii'; codePoints = @(0x41, 0x53, 0x43, 0x49, 0x49) },
        [pscustomobject]@{ id = 'japanese'; codePoints = @(0x65E5, 0x672C, 0x8A9E) },
        [pscustomobject]@{ id = 'emoji'; codePoints = @(0x1F600) },
        [pscustomobject]@{ id = 'supplementary'; codePoints = @(0x2000B) },
        [pscustomobject]@{ id = 'combining'; codePoints = @(0x41, 0x030A) },
        [pscustomobject]@{ id = 'nfc'; codePoints = @(0x00E9) },
        [pscustomobject]@{ id = 'nfd'; codePoints = @(0x65, 0x0301) }
    )
}

function Get-Poc2C1Case {
    param([Parameter(Mandatory = $true)][string]$CaseId)

    $matches = @(Get-Poc2C1Cases | Where-Object { $_.id -ceq $CaseId })
    if ($matches.Count -ne 1) {
        throw ('Unknown PoC 2-C1 case id: {0}' -f $CaseId)
    }
    return $matches[0]
}

function Get-Poc2C1CaseToken {
    param([Parameter(Mandatory = $true)]$Case)
    return (New-StringFromCodePoints -CodePoints ([int[]]$Case.codePoints))
}

function Get-Poc2C1CaseName {
    param([Parameter(Mandatory = $true)]$Case)
    return ('case-{0}-{1}' -f $Case.id, (Get-Poc2C1CaseToken -Case $Case))
}

function Get-Poc2C1CombinedToken {
    $codePoints = @(
        0x65E5, 0x672C, 0x8A9E,
        0x2D,
        0x1F600,
        0x2D,
        0x2000B,
        0x2D,
        0x65, 0x0301
    )
    return (New-StringFromCodePoints -CodePoints $codePoints)
}

function Get-RelativePathText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $rootFull = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
    $full = (Get-Item -LiteralPath $FullPath -Force).FullName
    return $full.Substring($rootFull.Length).TrimStart('\').Replace('\', '/')
}

function Get-UnicodeDirectoryInventory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
            directories = @()
            files = @()
            fingerprint = $null
            archiveSemanticFingerprint = $null
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

    $archiveCanonical = @()
    foreach ($file in ($files | Sort-Object relativePath)) {
        $archiveCanonical += ('F|{0}|{1}' -f (($file.unicode.codePoints) -join ','), $file.sizeBytes)
    }

    return [pscustomobject]@{
        path = $root
        exists = $true
        directories = @($dirs)
        files = @($files)
        fingerprint = Get-StringSha256 -Text ($canonical -join "`n")
        archiveSemanticFingerprint = Get-StringSha256 -Text ($archiveCanonical -join "`n")
    }
}

function Get-ZipUnicodeInventory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
            entries = @()
            fileFingerprint = $null
        }
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        $zip = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false
        )
        try {
            $entries = @()
            foreach ($entry in ($zip.Entries | Sort-Object FullName)) {
                $name = $entry.FullName.Replace('\', '/')
                $isDirectory = $name.EndsWith('/')
                $entries += [pscustomobject]@{
                    fullName = $name
                    unicode = Get-UnicodeStringEvidence -Text $name
                    isDirectory = $isDirectory
                    length = [Int64]$entry.Length
                    compressedLength = [Int64]$entry.CompressedLength
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

    $canonical = @()
    foreach ($entry in ($entries | Where-Object { -not $_.isDirectory } | Sort-Object fullName)) {
        $canonical += ('F|{0}|{1}' -f (($entry.unicode.codePoints) -join ','), $entry.length)
    }

    return [pscustomobject]@{
        path = (Get-Item -LiteralPath $Path).FullName
        exists = $true
        entries = @($entries)
        fileFingerprint = Get-StringSha256 -Text ($canonical -join "`n")
    }
}

function New-ReferenceUnicodeZip {
    param(
        [Parameter(Mandatory = $true)][string]$InputRoot,
        [Parameter(Mandatory = $true)][string]$ZipPath
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    $stream = [System.IO.File]::Open(
        $ZipPath,
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

            foreach ($dir in Get-ChildItem -LiteralPath $InputRoot -Recurse -Force -Directory | Sort-Object FullName) {
                $relative = $dir.FullName.Substring((Get-Item -LiteralPath $InputRoot).FullName.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
                $entry = $zip.CreateEntry($relative + '/', [System.IO.Compression.CompressionLevel]::NoCompression)
                $entry.LastWriteTime = $fixedTime
            }

            foreach ($file in Get-ChildItem -LiteralPath $InputRoot -Recurse -Force -File | Sort-Object FullName) {
                $relative = $file.FullName.Substring((Get-Item -LiteralPath $InputRoot).FullName.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
                $entry = $zip.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::NoCompression)
                $entry.LastWriteTime = $fixedTime
                $entryStream = $entry.Open()
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
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
}

function New-Poc2C1Fixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    $inputRoot = Join-Path $Root 'unicode-input'
    New-Item -ItemType Directory -Path $inputRoot -Force | Out-Null

    [System.IO.File]::WriteAllText(
        (Join-Path $inputRoot 'root.txt'),
        "root payload`r`n",
        [System.Text.Encoding]::ASCII
    )

    $caseEvidence = @()
    foreach ($case in Get-Poc2C1Cases) {
        $token = Get-Poc2C1CaseToken -Case $case
        $caseName = Get-Poc2C1CaseName -Case $case
        $dirPath = Join-Path $inputRoot $caseName
        New-Item -ItemType Directory -Path $dirPath -Force | Out-Null

        $fileName = ('payload-{0}-{1}.txt' -f $case.id, $token)
        $filePath = Join-Path $dirPath $fileName
        [System.IO.File]::WriteAllText(
            $filePath,
            ('case={0}' -f $case.id) + "`r`npayload=0123456789`r`n",
            [System.Text.Encoding]::ASCII
        )

        $caseEvidence += [pscustomobject]@{
            id = $case.id
            token = Get-UnicodeStringEvidence -Text $token
            caseName = Get-UnicodeStringEvidence -Text $caseName
            fileName = Get-UnicodeStringEvidence -Text $fileName
        }
    }

    $combinedName = 'source-all-' + (Get-Poc2C1CombinedToken)
    $combinedRoot = Join-Path $Root $combinedName
    New-Item -ItemType Directory -Path $combinedRoot -Force | Out-Null
    foreach ($child in Get-ChildItem -LiteralPath $inputRoot -Force) {
        Copy-Item -LiteralPath $child.FullName -Destination $combinedRoot -Recurse -Force
    }

    $referenceZip = Join-Path $Root 'reference-unicode.zip'
    New-ReferenceUnicodeZip -InputRoot $inputRoot -ZipPath $referenceZip

	$pathProbeRoot = Join-Path $Root 'pathprobe-input'
	New-Item -ItemType Directory -Path $pathProbeRoot -Force | Out-Null
	[System.IO.File]::WriteAllText(
		(Join-Path $pathProbeRoot 'probe.txt'),
		"pathprobe payload`r`n",
		[System.Text.Encoding]::ASCII
	)
	$pathProbeReferenceZip = Join-Path $Root 'pathprobe-reference.zip'
	New-ReferenceUnicodeZip -InputRoot $pathProbeRoot -ZipPath $pathProbeReferenceZip

    $archivePathsRoot = Join-Path $Root 'archive-paths'
    New-Item -ItemType Directory -Path $archivePathsRoot -Force | Out-Null
    $archivePathEvidence = @()
    foreach ($case in Get-Poc2C1Cases) {
        $caseName = Get-Poc2C1CaseName -Case $case
        $archiveName = 'archive-' + $caseName + '.zip'
        $archivePath = Join-Path $archivePathsRoot $archiveName
        Copy-Item -LiteralPath $pathProbeReferenceZip -Destination $archivePath -Force
        $archivePathEvidence += [pscustomobject]@{
            id = $case.id
            fileName = Get-UnicodeStringEvidence -Text $archiveName
            sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    $inputInventory = Get-UnicodeDirectoryInventory -Path $inputRoot
    $combinedInventory = Get-UnicodeDirectoryInventory -Path $combinedRoot
    $zipEvidence = Get-FileHashEvidence -Path $referenceZip
    $zipInventory = Get-ZipUnicodeInventory -Path $referenceZip
	$pathProbeInventory = Get-UnicodeDirectoryInventory -Path $pathProbeRoot
	$pathProbeZipEvidence = Get-FileHashEvidence -Path $pathProbeReferenceZip
	$pathProbeZipInventory = Get-ZipUnicodeInventory -Path $pathProbeReferenceZip

	if ([string]$pathProbeZipInventory.fileFingerprint -cne [string]$pathProbeInventory.archiveSemanticFingerprint) {
		throw 'Path Probe reference ZIP semantic fingerprint does not match the ASCII-only source fixture.'
	}
	$nonAsciiEntries = @($pathProbeZipInventory.entries | Where-Object { [string]$_.fullName -match '[^\x00-\x7F]' })
	if ($nonAsciiEntries.Count -ne 0) {
		throw 'Path Probe reference ZIP contains a non-ASCII entry name.'
	}

    return [pscustomobject]@{
        root = $Root
        inputRoot = $inputRoot
        inputInventory = $inputInventory
        combinedRoot = $combinedRoot
        combinedRootName = Get-UnicodeStringEvidence -Text $combinedName
        combinedInventory = $combinedInventory
        referenceZip = $zipEvidence
        referenceZipEntries = $zipInventory
		pathProbeRoot = $pathProbeRoot
		pathProbeInventory = $pathProbeInventory
		pathProbeReferenceZip = $pathProbeZipEvidence
		pathProbeReferenceZipEntries = $pathProbeZipInventory
        cases = @($caseEvidence)
        archivePaths = @($archivePathEvidence)
    }
}

function Get-ExternalState {
    $appData = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'LhaForge'
    $programData = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'LhaForge'
    return [pscustomobject]@{
        appData = Get-UnicodeDirectoryInventory -Path $appData
        programData = Get-UnicodeDirectoryInventory -Path $programData
    }
}

function Get-TempZipState {
    $items = @()
    if (Test-Path -LiteralPath $env:TEMP -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $env:TEMP -Filter 'zip*.tmp' -Force -File -ErrorAction SilentlyContinue | Sort-Object FullName) {
            $items += [pscustomobject]@{
                path = $file.FullName
                sizeBytes = [Int64]$file.Length
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    return @($items)
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-KitRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-TargetRoot {
    param([Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target)
    return (Join-Path (Get-KitRoot) $Target)
}

function Get-RunRecordRoot {
    param([Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target)
    return (Join-Path (Get-TargetRoot -Target $Target) 'results\run-records')
}

function Get-RunRecordPath {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
        [Parameter(Mandatory = $true)][string]$Operation,
        [string]$CaseId
    )

    $name = $Operation
    if (-not [string]::IsNullOrWhiteSpace($CaseId)) {
        $name += '-' + $CaseId
    }
    return (Join-Path (Get-RunRecordRoot -Target $Target) ($name + '.json'))
}

function Save-RunRecord {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
        [Parameter(Mandatory = $true)][string]$Operation,
        [string]$CaseId,
        [Parameter(Mandatory = $true)]$Record
    )

    $root = Get-RunRecordRoot -Target $Target
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $path = Get-RunRecordPath -Target $Target -Operation $Operation -CaseId $CaseId
    Write-JsonUtf8NoBom -Value $Record -Path $path -Depth 18
    return $path
}

function Convert-ExitCodeToHex {
    param([Parameter(Mandatory = $true)][int]$ExitCode)
    $bytes = [System.BitConverter]::GetBytes($ExitCode)
    $unsigned = [System.BitConverter]::ToUInt32($bytes, 0)
    return ('0x{0:X8}' -f $unsigned)
}

function Test-ExitLooksLikeCrash {
    param([Parameter(Mandatory = $true)][int]$ExitCode)
    $hex = Convert-ExitCodeToHex -ExitCode $ExitCode
    return $hex.StartsWith('0xC', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ExternalInventoryEqual {
    param($Left, $Right)

    foreach ($name in @('appData', 'programData')) {
        $a = $Left.$name
        $b = $Right.$name
        if ([bool]$a.exists -ne [bool]$b.exists) { return $false }
        if ($a.exists -and ([string]$a.fingerprint -cne [string]$b.fingerprint)) { return $false }
    }
    return $true
}
