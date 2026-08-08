#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('original', 'modern')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateSet('list', 'test', 'extract', 'compress', 'reextract')]
    [string]$Operation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')

function Q {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-LhaForge {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.Arguments = ($Arguments -join ' ')

    Write-Host ('[POC2-ARCHIVE] Launch: {0} {1}' -f $Exe, $psi.Arguments)
    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
    Write-Host ('[POC2-ARCHIVE] Process exit code: {0}' -f $process.ExitCode)
    return $process.ExitCode
}

$kitRoot = Get-KitRoot
$targetRoot = Get-TargetRoot -Target $Target
$exe = Join-Path $targetRoot 'LhaForge.exe'
$config = Join-Path $targetRoot 'LhaForge.ini'
$referenceZip = Join-Path $kitRoot 'fixture\reference.zip'
$inputRoot = Join-Path $kitRoot 'fixture\input'
$resultsRoot = Join-Path $targetRoot 'results'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw ('LhaForge.exe was not found: {0}' -f $exe)
}

New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null

$cfgArg = Q ('/cfg:' + $config)

switch ($Operation) {
    'list' {
        $args = @($cfgArg, '/l', (Q $referenceZip))
        [void](Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args)
        Write-Host ''
        Write-Host 'Expected logical file tree:'
        Get-Content -LiteralPath (Join-Path $kitRoot 'fixture\EXPECTED_TREE.txt') | ForEach-Object { Write-Host ('  ' + $_) }
        Write-Host ''
        $answer = Read-Host 'Did the List window show the expected archive contents without an error? [y/n]'
        Save-ManualObservation -Target $Target -Operation 'list' -Passed ($answer -match '^[Yy]')
    }

    'test' {
        $args = @($cfgArg, '/t', (Q $referenceZip))
        [void](Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args)
        Write-Host ''
        $answer = Read-Host 'Did the archive test dialog report a successful test with no archive error? [y/n]'
        Save-ManualObservation -Target $Target -Operation 'test' -Passed ($answer -match '^[Yy]')
    }

    'extract' {
        $output = Join-Path $resultsRoot 'extract'
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
        New-Item -ItemType Directory -Path $output -Force | Out-Null

        $args = @(
            $cfgArg,
            '/e',
            (Q ('/o:' + $output)),
            '/mkdir:no',
            (Q $referenceZip)
        )
        [void](Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args)

        $inventory = Get-DirectoryInventory -Path $output
        Write-Host ('[POC2-ARCHIVE] Extracted files: {0}' -f $inventory.files.Count)
    }

    'compress' {
        $output = Join-Path $resultsRoot 'compressed'
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
        New-Item -ItemType Directory -Path $output -Force | Out-Null

        $args = @(
            $cfgArg,
            '/c:zip',
            (Q ('/o:' + $output)),
            (Q '/f:roundtrip.zip'),
            '/method:Deflate',
            '/level:5',
            '/popdir:yes',
            (Q $inputRoot)
        )
        [void](Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args)

        $archive = Join-Path $output 'roundtrip.zip'
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw ('Compressed archive was not created: {0}' -f $archive)
        }
        $evidence = Get-FileHashEvidence -Path $archive
        Write-Host ('[POC2-ARCHIVE] Created ZIP SHA-256: {0}' -f $evidence.sha256)
    }

    'reextract' {
        $archive = Join-Path $resultsRoot 'compressed\roundtrip.zip'
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw 'Run the compress operation before reextract.'
        }

        $output = Join-Path $resultsRoot 'roundtrip'
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
        New-Item -ItemType Directory -Path $output -Force | Out-Null

        $args = @(
            $cfgArg,
            '/e',
            (Q ('/o:' + $output)),
            '/mkdir:no',
            (Q $archive)
        )
        [void](Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args)

        $inventory = Get-DirectoryInventory -Path $output
        Write-Host ('[POC2-ARCHIVE] Re-extracted files: {0}' -f $inventory.files.Count)
    }
}

Write-Host ('[POC2-ARCHIVE] {0}/{1} completed.' -f $Target, $Operation)
