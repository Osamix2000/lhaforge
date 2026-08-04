Set-StrictMode -Version 2.0

$script:PoC2Extensions = @(
    '.lzh', '.lzs', '.lha', '.zip', '.jar', '.cab', '.7z', '.arj', '.rar',
    '.jak', '.gca', '.imp', '.ace', '.yz1', '.hki', '.bza', '.gza', '.ish',
    '.uue', '.bel', '.tar', '.gz', '.tgz', '.bz2', '.tbz', '.xz', '.txz',
    '.lzma', '.tlz', '.z', '.taz', '.cpio', '.a', '.lib', '.rpm', '.deb',
    '.iso'
)

$script:PoC2ShellClsids = @(
    '{713B479F-6F2B-48E9-B545-5591CCFE398F}',
    '{5E5B692B-D6ED-4103-A1FA-9A71A93DAC88}',
    '{B7584D74-DE0C-4DB5-80DD-42EEEDF42665}',
    '{00521ADB-148D-45C9-8021-7446EE35609D}'
)

$script:PoC2RegistryQueryKeys = @(
    'HKCR\*\shellex\ContextMenuHandlers',
    'HKCR\Directory\shellex\ContextMenuHandlers',
    'HKCR\Directory\Background\shellex\ContextMenuHandlers',
    'HKCR\Drive\shellex\ContextMenuHandlers',
    'HKCR\*\shellex\DragDropHandlers',
    'HKCR\Directory\shellex\DragDropHandlers',
    'HKCR\Drive\shellex\DragDropHandlers'
)

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

function Read-TextWithEncoding {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encodingName = 'unknown'
    $offset = 0
    $encoding = $null

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encodingName = 'utf-16le-bom'
        $encoding = New-Object System.Text.UnicodeEncoding($false, $true)
        $offset = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encodingName = 'utf-16be-bom'
        $encoding = New-Object System.Text.UnicodeEncoding($true, $true)
        $offset = 2
    }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encodingName = 'utf-8-bom'
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        $offset = 3
    }
    else {
        $encodingName = 'utf-8-no-bom'
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        $offset = 0
    }

    try {
        $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        $encodingName = 'cp932-fallback'
        $encoding = [System.Text.Encoding]::GetEncoding(932)
        $text = $encoding.GetString($bytes)
    }

    return [pscustomobject]@{
        encoding = $encodingName
        text = $text
    }
}

function Read-IniSemantic {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('INI file was not found: {0}' -f $Path)
    }

    $decoded = Read-TextWithEncoding -Path $Path
    $section = ''
    $map = @{}

    foreach ($rawLine in [System.Text.RegularExpressions.Regex]::Split($decoded.text, "`r`n|`n|`r")) {
        $line = [string]$rawLine
        if ($line.Length -eq 0) { continue }
        if ($line[0] -eq ';') { continue }

        if ($line.StartsWith('[')) {
            $end = $line.IndexOf(']')
            if ($end -le 1) {
                throw ('Invalid INI section line: {0}' -f $line)
            }
            $section = $line.Substring(1, $end - 1)
            continue
        }

        $equals = $line.IndexOf('=')
        if ($equals -lt 0) {
            throw ('Invalid INI data line: {0}' -f $line)
        }
        if ([string]::IsNullOrEmpty($section)) {
            throw ('INI key before section: {0}' -f $line)
        }

        $key = $line.Substring(0, $equals)
        $value = $line.Substring($equals + 1)
        $composite = $section + "`n" + $key
        $map[$composite] = [pscustomobject]@{
            section = $section
            key = $key
            value = $value
        }
    }

    $entries = @($map.Values | Sort-Object section, key)
    return [pscustomobject]@{
        path = (Get-Item -LiteralPath $Path).FullName
        encoding = $decoded.encoding
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        entries = $entries
    }
}

function Get-IniValue {
    param(
        [Parameter(Mandatory = $true)]$Ini,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )

    foreach ($entry in $Ini.entries) {
        if ($entry.section -ceq $Section -and $entry.key -ceq $Key) {
            return [string]$entry.value
        }
    }
    return $null
}

function Get-DirectoryState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
            files = @()
            fingerprint = $null
        }
    }

    $root = (Get-Item -LiteralPath $Path).FullName
    $items = @()
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        $items += [pscustomobject]@{
            relativePath = $relative
            sizeBytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    $canonical = ($items | ConvertTo-Json -Depth 5 -Compress)
    return [pscustomobject]@{
        path = $root
        exists = $true
        files = $items
        fingerprint = Get-StringSha256 -Text $canonical
    }
}

function Convert-RegistryKeyToProviderPath {
    param([Parameter(Mandatory = $true)][string]$Key)

    $separator = $Key.IndexOf('\')
    if ($separator -lt 0) {
        $rootName = $Key
        $subKey = ''
    }
    else {
        $rootName = $Key.Substring(0, $separator)
        $subKey = $Key.Substring($separator + 1)
    }

    switch ($rootName.ToUpperInvariant()) {
        'HKCR' { $providerRoot = 'Registry::HKEY_CLASSES_ROOT' }
        'HKCU' { $providerRoot = 'Registry::HKEY_CURRENT_USER' }
        'HKLM' { $providerRoot = 'Registry::HKEY_LOCAL_MACHINE' }
        'HKU'  { $providerRoot = 'Registry::HKEY_USERS' }
        'HKCC' { $providerRoot = 'Registry::HKEY_CURRENT_CONFIG' }
        default { throw ('Unsupported registry root: {0}' -f $rootName) }
    }

    if ([string]::IsNullOrEmpty($subKey)) {
        return $providerRoot
    }

    return $providerRoot + '\' + $subKey
}

function Get-RegistryQueryState {
    param([Parameter(Mandatory = $true)][string]$Key)

    $providerPath = Convert-RegistryKeyToProviderPath -Key $Key
    if (-not (Test-Path -LiteralPath $providerPath)) {
        return [pscustomobject]@{
            key = $Key
            exists = $false
            fingerprint = $null
        }
    }

    # A missing registry key is an expected state on a clean VM. Do not merge
    # reg.exe stderr into the PowerShell error stream because Windows
    # PowerShell 5.1 converts it to NativeCommandError when
    # $ErrorActionPreference is Stop.
    $output = @(& reg.exe query $Key /s 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ('reg.exe failed for an existing registry key. Exit code {0}: {1}' -f $exitCode, $Key)
    }

    $queryText = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    return [pscustomobject]@{
        key = $Key
        exists = $true
        fingerprint = Get-StringSha256 -Text $queryText
    }
}

function Get-LhaForgeIntegrationIndicators {
    $indicators = @()
    $root = [Microsoft.Win32.Registry]::ClassesRoot

    foreach ($ext in $script:PoC2Extensions) {
        $key = $root.OpenSubKey($ext)
        if ($null -ne $key) {
            try {
                $value = [string]$key.GetValue('', '')
                if ($value.StartsWith('LhaForgeArchive_', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $indicators += ('Association {0} -> {1}' -f $ext, $value)
                }
            }
            finally {
                $key.Close()
            }
        }
    }

    foreach ($name in $root.GetSubKeyNames()) {
        if ($name.StartsWith('LhaForgeArchive_', [System.StringComparison]::OrdinalIgnoreCase)) {
            $indicators += ('Class key HKCR\{0}' -f $name)
        }
    }

    foreach ($clsid in $script:PoC2ShellClsids) {
        $key = $root.OpenSubKey('CLSID\' + $clsid)
        if ($null -ne $key) {
            try {
                $indicators += ('Shell extension HKCR\CLSID\{0}' -f $clsid)
            }
            finally {
                $key.Close()
            }
        }
    }

    return @($indicators)
}

function Get-RegistryState {
    $states = @()
    foreach ($key in $script:PoC2RegistryQueryKeys) {
        $states += Get-RegistryQueryState -Key $key
    }
    foreach ($ext in $script:PoC2Extensions) {
        $states += Get-RegistryQueryState -Key ('HKCR\' + $ext)
    }
    foreach ($clsid in $script:PoC2ShellClsids) {
        $states += Get-RegistryQueryState -Key ('HKCR\CLSID\' + $clsid)
    }
    return @($states | Sort-Object key)
}

function Get-ExternalState {
    $appData = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'LhaForge'
    $programData = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'LhaForge'

    return [pscustomobject]@{
        appData = Get-DirectoryState -Path $appData
        programData = Get-DirectoryState -Path $programData
        registry = Get-RegistryState
        integrationIndicators = @(Get-LhaForgeIntegrationIndicators)
    }
}

function Convert-ToCanonicalJson {
    param([Parameter(Mandatory = $true)]$Value)
    return ($Value | ConvertTo-Json -Depth 12 -Compress)
}
