Set-StrictMode -Version 2.0

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
        throw ('File was not found: {0}' -f $Path)
    }

    $file = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        path = $file.FullName
        sizeBytes = $file.Length
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
        sizeBytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        peMachine = ('0x{0:x4}' -f $machine)
        architecture = if ($machine -eq 0x014C) { 'x86' } else { 'other' }
        fileVersion = [string]$version.FileVersion
        productVersion = [string]$version.ProductVersion
    }
}

function Get-DirectoryInventory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
            files = @()
            fingerprint = $null
        }
    }

    $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    $items = @()
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $items += [pscustomobject]@{
            relativePath = $relative
            sizeBytes = [Int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    $canonical = (($items | ForEach-Object {
        '{0}|{1}|{2}' -f $_.relativePath, $_.sizeBytes, $_.sha256
    }) -join "`n")

    return [pscustomobject]@{
        path = $root
        exists = $true
        files = $items
        fingerprint = Get-StringSha256 -Text $canonical
    }
}

function Get-ZipInventory {
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

    $fileItems = @($entries | Where-Object { -not $_.isDirectory })
    $canonical = (($fileItems | ForEach-Object {
        '{0}|{1}' -f $_.fullName, $_.length
    }) -join "`n")

    return [pscustomobject]@{
        path = (Get-Item -LiteralPath $Path).FullName
        exists = $true
        entries = $entries
        fileFingerprint = Get-StringSha256 -Text $canonical
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

function Get-ExternalState {
    $appData = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'LhaForge'
    $programData = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'LhaForge'
    return [pscustomobject]@{
        appData = Get-DirectoryInventory -Path $appData
        programData = Get-DirectoryInventory -Path $programData
    }
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

function Get-ManualObservationPath {
    param([Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target)
    return (Join-Path (Join-Path (Get-KitRoot) 'evidence') ($Target + '-manual.json'))
}

function Save-ManualObservation {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
        [Parameter(Mandatory = $true)][ValidateSet('list', 'test')][string]$Operation,
        [Parameter(Mandatory = $true)][bool]$Passed
    )

    $path = Get-ManualObservationPath -Target $Target
    $state = [ordered]@{
        target = $Target
        list = $null
        test = $null
        updatedUtc = [DateTime]::UtcNow.ToString('o')
    }

    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $state.list = $existing.list
        $state.test = $existing.test
    }

    $state[$Operation] = $Passed
    $state.updatedUtc = [DateTime]::UtcNow.ToString('o')
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Test-InventoryEqual {
    param($Left, $Right)
    if (-not $Left.exists -or -not $Right.exists) { return $false }
    return ([string]$Left.fingerprint -ceq [string]$Right.fingerprint)
}

function Get-ZipFileEntryFingerprintFromDirectoryInventory {
    param([Parameter(Mandatory = $true)]$Inventory)
    $canonical = (($Inventory.files | Sort-Object relativePath | ForEach-Object {
        '{0}|{1}' -f $_.relativePath, $_.sizeBytes
    }) -join "`n")
    return Get-StringSha256 -Text $canonical
}
