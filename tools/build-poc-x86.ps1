#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$verifyScript = Join-Path $PSScriptRoot 'verify-vs-environment.ps1'
$solutionPath = Join-Path $repoRoot 'LhaForge.sln'

if (-not (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
    throw ('Environment verifier was not found: {0}' -f $verifyScript)
}

if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
    throw ('Solution was not found: {0}' -f $solutionPath)
}

Write-Host '[BUILD] Verifying development environment...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw ('vswhere was not found: {0}' -f $vswhere)
}

$installationPath = & $vswhere -latest -products '*' -version '[18.0,19.0)' -property installationPath | Select-Object -First 1
if ($null -ne $installationPath) {
    $installationPath = $installationPath.Trim()
}
if ([string]::IsNullOrWhiteSpace($installationPath)) {
    throw 'Visual Studio 2026 installation was not found.'
}

$msbuild = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild -PathType Leaf)) {
    throw ('MSBuild was not found: {0}' -f $msbuild)
}

$target = if ($Rebuild) { 'Rebuild' } else { 'Build' }

Write-Host ''
Write-Host ('[BUILD] Configuration: {0}|Win32' -f $Configuration)
Write-Host ('[BUILD] Target: {0}' -f $target)
Write-Host ('[BUILD] MSBuild: {0}' -f $msbuild)
Write-Host ''

$arguments = @(
    $solutionPath,
    '/nologo',
    '/m',
    ('/t:{0}' -f $target),
    ('/p:Configuration={0}' -f $Configuration),
    '/p:Platform=Win32',
    '/verbosity:minimal'
)

& $msbuild @arguments
$exitCode = $LASTEXITCODE

Write-Host ''
if ($exitCode -eq 0) {
    Write-Host ('[BUILD] {0}|Win32 completed successfully.' -f $Configuration)
}
else {
    Write-Host ('[BUILD] {0}|Win32 failed with exit code {1}.' -f $Configuration, $exitCode)
    Write-Host '[BUILD] Keep compiler/MSBuild errors unchanged and record the failure before applying a fix.'
}

exit $exitCode
