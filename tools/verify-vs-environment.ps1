#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-CheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Ok,
        [string]$Detail = ''
    )

    $state = if ($Ok) { 'OK' } else { 'NG' }
    if ($Detail) {
        Write-Host ('[{0}] {1}: {2}' -f $state, $Name, $Detail)
    }
    else {
        Write-Host ('[{0}] {1}' -f $state, $Name)
    }
}

$failed = $false

$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'

if (-not (Test-Path -LiteralPath $vswhere)) {
    Write-CheckResult -Name 'Visual Studio Installer / vswhere' -Ok $false -Detail $vswhere
    Write-Host ''
    Write-Host 'Install Visual Studio Community 2026 Stable and import the repository .vsconfig file.'
    exit 2
}

Write-CheckResult -Name 'Visual Studio Installer / vswhere' -Ok $true -Detail $vswhere

$requiredComponents = @(
    'Microsoft.VisualStudio.ComponentGroup.VC.Tools.143.x86.x64',
    'Microsoft.VisualStudio.Component.VC.14.44.17.14.ATL',
    'Microsoft.VisualStudio.Component.Windows11SDK.26100'
)

$vswhereArgs = @(
    '-latest',
    '-products', '*',
    '-version', '[18.0,19.0)',
    '-requires'
) + $requiredComponents + @(
    '-property', 'installationPath'
)

$installationPath = & $vswhere @vswhereArgs | Select-Object -First 1
if ($null -ne $installationPath) {
    $installationPath = $installationPath.Trim()
}

if ([string]::IsNullOrWhiteSpace($installationPath)) {
    Write-CheckResult -Name 'Visual Studio 2026 + required components' -Ok $false -Detail 'Required component set was not found.'
    $failed = $true
}
else {
    Write-CheckResult -Name 'Visual Studio 2026 + required components' -Ok $true -Detail $installationPath

    # Do not pipe vswhere UTF-8 JSON directly into ConvertFrom-Json here.
    # Windows PowerShell 5.1 can decode native-process UTF-8 output using the
    # active legacy code page, which can corrupt localized JSON string values.
    # Query only ASCII-valued properties that are needed by this verifier.
    $versionArgs = @(
        '-latest',
        '-products', '*',
        '-version', '[18.0,19.0)',
        '-requires'
    ) + $requiredComponents + @(
        '-property', 'installationVersion'
    )

    $installationVersion = & $vswhere @versionArgs | Select-Object -First 1
    if ($null -ne $installationVersion) {
        $installationVersion = $installationVersion.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($installationVersion)) {
        Write-Host ('      Installation version: {0}' -f $installationVersion)
    }

    $msbuild = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
    $vcvars = Join-Path $installationPath 'VC\Auxiliary\Build\vcvarsall.bat'

    $msbuildOk = Test-Path -LiteralPath $msbuild
    $vcvarsOk = Test-Path -LiteralPath $vcvars

    Write-CheckResult -Name 'MSBuild' -Ok $msbuildOk -Detail $msbuild
    Write-CheckResult -Name 'vcvarsall.bat' -Ok $vcvarsOk -Detail $vcvars

    if (-not $msbuildOk -or -not $vcvarsOk) {
        $failed = $true
    }

    $msvcRoot = Join-Path $installationPath 'VC\Tools\MSVC'
    $msvcVersions = @()
    if (Test-Path -LiteralPath $msvcRoot) {
        $msvcVersions = @(
            Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '14.44.*' } |
                Sort-Object Name
        )
    }

    if ($msvcVersions.Count -eq 0) {
        Write-CheckResult -Name 'MSVC v143 / 14.44 family' -Ok $false -Detail $msvcRoot
        $failed = $true
    }
    else {
        $selectedMsvc = $msvcVersions[-1]
        $clX86 = Join-Path $selectedMsvc.FullName 'bin\Hostx64\x86\cl.exe'
        $clX64 = Join-Path $selectedMsvc.FullName 'bin\Hostx64\x64\cl.exe'
        $atlBaseHeader = Join-Path $selectedMsvc.FullName 'atlmfc\include\atlbase.h'
        $atlWinHeader = Join-Path $selectedMsvc.FullName 'atlmfc\include\atlwin.h'

        $clX86Ok = Test-Path -LiteralPath $clX86
        $clX64Ok = Test-Path -LiteralPath $clX64
        $atlBaseOk = Test-Path -LiteralPath $atlBaseHeader
        $atlWinOk = Test-Path -LiteralPath $atlWinHeader
        $atlOk = $atlBaseOk -and $atlWinOk

        Write-CheckResult -Name 'MSVC v143 / 14.44 family' -Ok ($clX86Ok -and $clX64Ok) -Detail $selectedMsvc.Name
        Write-CheckResult -Name 'MSVC x86 compiler' -Ok $clX86Ok -Detail $clX86
        Write-CheckResult -Name 'MSVC x64 compiler' -Ok $clX64Ok -Detail $clX64
        Write-CheckResult -Name 'ATL 14.44 atlbase.h' -Ok $atlBaseOk -Detail $atlBaseHeader
        Write-CheckResult -Name 'ATL 14.44 atlwin.h' -Ok $atlWinOk -Detail $atlWinHeader

        if (-not $clX86Ok -or -not $clX64Ok -or -not $atlOk) {
            $failed = $true
        }
    }
}

$sdkIncludeRoot = Join-Path $programFilesX86 'Windows Kits\10\Include'
$sdkVersions = @()
if (Test-Path -LiteralPath $sdkIncludeRoot) {
    $sdkVersions = @(
        Get-ChildItem -LiteralPath $sdkIncludeRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '10.0.26100.*' } |
            Sort-Object Name
    )
}

if ($sdkVersions.Count -eq 0) {
    Write-CheckResult -Name 'Windows SDK 26100 family' -Ok $false -Detail $sdkIncludeRoot
    $failed = $true
}
else {
    Write-CheckResult -Name 'Windows SDK 26100 family' -Ok $true -Detail (($sdkVersions.Name) -join ', ')
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$wtlManifest = Join-Path $repoRoot 'dependencies\wtl.json'
if (-not (Test-Path -LiteralPath $wtlManifest -PathType Leaf)) {
    Write-CheckResult -Name 'WTL dependency manifest' -Ok $false -Detail $wtlManifest
    $failed = $true
}
else {
    $wtlConfig = Get-Content -LiteralPath $wtlManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $wtlVersion = [string]$wtlConfig.defaultVersion
    $wtlPackage = @($wtlConfig.packages | Where-Object { [string]$_.version -eq $wtlVersion }) | Select-Object -First 1
    $wtlInclude = Join-Path $repoRoot ('.deps\wtl\{0}\Include' -f $wtlVersion)
    $wtlHeader = Join-Path $wtlInclude 'atlapp.h'
    $wtlMetadataPath = Join-Path $repoRoot ('.deps\wtl\{0}\.restore-metadata.json' -f $wtlVersion)
    $wtlOk = (Test-Path -LiteralPath $wtlHeader -PathType Leaf) -and ($null -ne $wtlPackage)

    if ($wtlOk -and (Test-Path -LiteralPath $wtlMetadataPath -PathType Leaf)) {
        try {
            $wtlMetadata = Get-Content -LiteralPath $wtlMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $wtlOk = (([string]$wtlMetadata.version -eq $wtlVersion) -and
                ([string]$wtlMetadata.sha256 -eq ([string]$wtlPackage.sha256).ToLowerInvariant()))
        }
        catch {
            $wtlOk = $false
        }
    }
    else {
        $wtlOk = $false
    }

    Write-CheckResult -Name ('WTL {0}' -f $wtlVersion) -Ok $wtlOk -Detail $wtlInclude
    if (-not $wtlOk) {
        Write-Host '      Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\restore-wtl.ps1'
        $failed = $true
    }
}

Write-Host ''
Write-Host 'This script does not retarget projects or start a build.'

if ($failed) {
    Write-Host ''
    Write-Host 'Environment verification failed.'
    exit 1
}

Write-Host ''
Write-Host 'Environment verification passed.'
exit 0
