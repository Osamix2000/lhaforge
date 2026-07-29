#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$ArchivePath = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ('[WTL] {0}' -f $Message)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ArchiveHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    return ((Get-Sha256 -Path $Path) -eq $Expected.ToLowerInvariant())
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'dependencies\wtl.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw ('Dependency manifest not found: {0}' -f $configPath)
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string]$config.defaultVersion
}

$package = @($config.packages | Where-Object { [string]$_.version -eq $Version }) | Select-Object -First 1
if ($null -eq $package) {
    $known = @($config.packages | ForEach-Object { [string]$_.version }) -join ', '
    throw ('Unsupported WTL version: {0}. Known versions: {1}' -f $Version, $known)
}

$expectedHash = ([string]$package.sha256).ToLowerInvariant()
$archiveName = [string]$package.archive
$depsRoot = Join-Path $repoRoot '.deps'
$cacheRoot = Join-Path $depsRoot 'cache\wtl'
$wtlRoot = Join-Path $depsRoot 'wtl'
$targetRoot = Join-Path $wtlRoot $Version
$metadataPath = Join-Path $targetRoot '.restore-metadata.json'
$requiredHeaders = @(
    'Include\atlapp.h',
    'Include\atlcrack.h',
    'Include\atlctrls.h',
    'Include\atlframe.h',
    'Include\atlmisc.h'
)

$existingValid = $true
foreach ($relativeHeader in $requiredHeaders) {
    if (-not (Test-Path -LiteralPath (Join-Path $targetRoot $relativeHeader) -PathType Leaf)) {
        $existingValid = $false
        break
    }
}

if ($existingValid -and (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    try {
        $existingMetadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (([string]$existingMetadata.version -ne $Version) -or
            ([string]$existingMetadata.sha256 -ne $expectedHash)) {
            $existingValid = $false
        }
    }
    catch {
        $existingValid = $false
    }
}
else {
    $existingValid = $false
}

if ($existingValid -and -not $Force) {
    Write-Step ('WTL {0} is already restored and verified: {1}' -f $Version, $targetRoot)
    Write-Step 'Use -Force to replace the restored copy.'
    exit 0
}

if ((Test-Path -LiteralPath $targetRoot) -and -not $Force) {
    throw ('Existing WTL target is incomplete or unverified: {0}. Rerun with -Force.' -f $targetRoot)
}

if ($Force -and (Test-Path -LiteralPath $targetRoot)) {
    Write-Step ('Removing existing target: {0}' -f $targetRoot)
    Remove-Item -LiteralPath $targetRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
New-Item -ItemType Directory -Path $wtlRoot -Force | Out-Null

$archiveToUse = $null
$sourceUsed = $null

if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
    $resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
    Write-Step ('Checking local archive: {0}' -f $resolvedArchive)
    if (-not (Test-ArchiveHash -Path $resolvedArchive -Expected $expectedHash)) {
        $actualHash = Get-Sha256 -Path $resolvedArchive
        throw ('SHA-256 mismatch. Expected {0}, actual {1}' -f $expectedHash, $actualHash)
    }
    $archiveToUse = $resolvedArchive
    $sourceUsed = 'local:' + $resolvedArchive
}
else {
    $cachedArchive = Join-Path $cacheRoot $archiveName
    if (Test-ArchiveHash -Path $cachedArchive -Expected $expectedHash) {
        Write-Step ('Using verified cache: {0}' -f $cachedArchive)
        $archiveToUse = $cachedArchive
        $sourceUsed = 'cache:' + $cachedArchive
    }
    else {
        if (Test-Path -LiteralPath $cachedArchive) {
            Write-Step ('Removing invalid cache: {0}' -f $cachedArchive)
            Remove-Item -LiteralPath $cachedArchive -Force
        }

        # Enable TLS 1.2 for Windows PowerShell 5.1 dependency downloads.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $downloadErrors = New-Object System.Collections.Generic.List[string]
        foreach ($uri in @($package.uris)) {
            $uriText = [string]$uri
            $partPath = $cachedArchive + '.part'
            if (Test-Path -LiteralPath $partPath) {
                Remove-Item -LiteralPath $partPath -Force
            }

            try {
                Write-Step ('Downloading: {0}' -f $uriText)
                Invoke-WebRequest -UseBasicParsing -Uri $uriText -OutFile $partPath -UserAgent 'LhaForge-dependency-bootstrap/1.0'

                if (Test-ArchiveHash -Path $partPath -Expected $expectedHash) {
                    Move-Item -LiteralPath $partPath -Destination $cachedArchive -Force
                    $archiveToUse = $cachedArchive
                    $sourceUsed = $uriText
                    Write-Step ('SHA-256 verified: {0}' -f $expectedHash)
                    break
                }

                $actualHash = Get-Sha256 -Path $partPath
                $downloadErrors.Add(('Hash mismatch from {0}. Actual: {1}' -f $uriText, $actualHash))
                Remove-Item -LiteralPath $partPath -Force
            }
            catch {
                if (Test-Path -LiteralPath $partPath) {
                    Remove-Item -LiteralPath $partPath -Force
                }
                $downloadErrors.Add(('{0}: {1}' -f $uriText, $_.Exception.Message))
            }
        }

        if ($null -eq $archiveToUse) {
            $details = $downloadErrors -join [Environment]::NewLine
            throw ("Unable to download a verified WTL archive. Download it manually and rerun with -ArchivePath.`n{0}" -f $details)
        }
    }
}

$stagingRoot = Join-Path $depsRoot ('staging\wtl-' + [Guid]::NewGuid().ToString('N'))
$restoreSucceeded = $false
try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    Write-Step ('Extracting: {0}' -f $archiveToUse)
    Expand-Archive -LiteralPath $archiveToUse -DestinationPath $stagingRoot -Force

    $atlAppCandidates = @(
        Get-ChildItem -LiteralPath $stagingRoot -Filter 'atlapp.h' -File -Recurse -ErrorAction Stop |
            Where-Object { $_.Directory.Name -eq 'Include' }
    )

    if ($atlAppCandidates.Count -ne 1) {
        throw ('Expected exactly one Include\\atlapp.h in the WTL archive, found {0}.' -f $atlAppCandidates.Count)
    }

    $includeDir = $atlAppCandidates[0].Directory.FullName
    $packageRoot = Split-Path -Parent $includeDir

    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $packageRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $targetRoot -Recurse -Force
    }

    foreach ($relativeHeader in $requiredHeaders) {
        $headerPath = Join-Path $targetRoot $relativeHeader
        if (-not (Test-Path -LiteralPath $headerPath -PathType Leaf)) {
            throw ('Restored WTL is incomplete. Missing: {0}' -f $headerPath)
        }
    }

    $metadata = [ordered]@{
        schemaVersion = 1
        dependency = 'WTL'
        version = $Version
        archive = $archiveName
        sha256 = $expectedHash
        source = $sourceUsed
        restoredUtc = [DateTime]::UtcNow.ToString('o')
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding UTF8

    Write-Step ('Restored WTL {0}: {1}' -f $Version, $targetRoot)
    Write-Step ('Include path: {0}' -f (Join-Path $targetRoot 'Include'))
    Write-Step 'No administrator privileges are required for this restore.'
    $restoreSucceeded = $true
}
finally {
    if (-not $restoreSucceeded -and (Test-Path -LiteralPath $targetRoot)) {
        Remove-Item -LiteralPath $targetRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
