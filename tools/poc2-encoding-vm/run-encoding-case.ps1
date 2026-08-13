#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('original', 'modern')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateSet('list', 'test', 'pathprobe', 'compress', 'reextract')]
    [string]$Operation,

    [string]$CaseId
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

    Write-Host ('[POC2-ENC] Launch: {0} {1}' -f $Exe, $psi.Arguments)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
    $stopwatch.Stop()

    $exitCode = [int]$process.ExitCode
    $exitHex = Convert-ExitCodeToHex -ExitCode $exitCode
    Write-Host ('[POC2-ENC] Process exit code: {0} ({1})' -f $exitCode, $exitHex)

    return [pscustomobject]@{
        exitCode = $exitCode
        exitCodeHex = $exitHex
        elapsedMs = [Int64]$stopwatch.ElapsedMilliseconds
        looksLikeCrash = Test-ExitLooksLikeCrash -ExitCode $exitCode
    }
}

$kitRoot = Get-KitRoot
$targetRoot = Get-TargetRoot -Target $Target
$exe = Join-Path $targetRoot 'LhaForge.exe'
$config = Join-Path $targetRoot 'LhaForge.ini'
$fixtureRoot = Join-Path $kitRoot 'fixture'
$referenceZip = Join-Path $fixtureRoot 'reference-unicode.zip'
$inputRoot = Join-Path $fixtureRoot 'unicode-input'
$resultsRoot = Join-Path $targetRoot 'results'
$beforePath = Join-Path $kitRoot 'evidence\state-before.json'

if (-not (Test-Path -LiteralPath $beforePath -PathType Leaf)) {
    throw 'Run initialize-encoding-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw ('LhaForge.exe was not found: {0}' -f $exe)
}

$before = Read-JsonUtf8 -Path $beforePath
$expectedFingerprint = [string]$before.fixture.inputInventory.fingerprint
$expectedArchiveFingerprint = [string]$before.fixture.inputInventory.archiveSemanticFingerprint
$cfgArg = Q ('/cfg:' + $config)

$record = [ordered]@{
    schemaVersion = 1
    target = $Target
    operation = $Operation
    caseId = if ([string]::IsNullOrWhiteSpace($CaseId)) { $null } else { $CaseId }
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    process = $null
    success = $false
    details = $null
}

switch ($Operation) {
    'list' {
        if (-not [string]::IsNullOrWhiteSpace($CaseId)) {
            throw 'CaseId is not used for list.'
        }

        $args = @($cfgArg, '/l', (Q $referenceZip))
        $process = Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $record.process = $process

        Write-Host ''
        Write-Host 'Expected file paths and code points:'
        foreach ($file in $before.fixture.inputInventory.files) {
            Write-Host ('  {0}' -f $file.relativePath)
            Write-Host ('    {0}' -f (($file.unicode.codePoints) -join ' '))
        }
        Write-Host ''

        $answer = Read-Host 'Did the List window show the expected names without mojibake or archive error? [y/n]'
        $passed = ($answer -match '^[Yy]')
        $record.success = $passed
        $record.details = [ordered]@{
            manualPassed = $passed
            expectedFileCount = @($before.fixture.inputInventory.files).Count
        }

        $path = Save-RunRecord -Target $Target -Operation $Operation -Record $record
        Write-Host ('[POC2-ENC] Evidence: {0}' -f $path)

        if ($process.looksLikeCrash) {
            throw ('LhaForge appears to have crashed: {0}' -f $process.exitCodeHex)
        }
        if (-not $passed) {
            throw 'Manual List observation failed. Stop and review before continuing.'
        }
    }

    'test' {
        if (-not [string]::IsNullOrWhiteSpace($CaseId)) {
            throw 'CaseId is not used for test.'
        }

        $args = @($cfgArg, '/t', (Q $referenceZip))
        $process = Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $record.process = $process

        Write-Host ''
        $answer = Read-Host 'Did the archive test complete without an archive error? [y/n]'
        $passed = ($answer -match '^[Yy]')
        $record.success = $passed
        $record.details = [ordered]@{
            manualPassed = $passed
        }

        $path = Save-RunRecord -Target $Target -Operation $Operation -Record $record
        Write-Host ('[POC2-ENC] Evidence: {0}' -f $path)

        if ($process.looksLikeCrash) {
            throw ('LhaForge appears to have crashed: {0}' -f $process.exitCodeHex)
        }
        if (-not $passed) {
            throw 'Manual Test observation failed. Stop and review before continuing.'
        }
    }

    'pathprobe' {
        if ([string]::IsNullOrWhiteSpace($CaseId)) {
            throw 'pathprobe requires -CaseId.'
        }

        $case = Get-Poc2C1Case -CaseId $CaseId
        $caseName = Get-Poc2C1CaseName -Case $case
        $archiveName = 'archive-' + $caseName + '.zip'
        $archivePath = Join-Path (Join-Path $fixtureRoot 'archive-paths') $archiveName

        $parent = Join-Path (Join-Path $resultsRoot 'pathprobe') $CaseId
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $outputName = 'output-' + $caseName
        $output = Join-Path $parent $outputName
        if (Test-Path -LiteralPath $output) {
            Remove-Item -LiteralPath $output -Recurse -Force
        }
        New-Item -ItemType Directory -Path $output -Force | Out-Null

        $args = @(
            $cfgArg,
            '/e',
            (Q ('/o:' + $output)),
            '/mkdir:no',
            (Q $archivePath)
        )
        $process = Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $inventory = Get-UnicodeDirectoryInventory -Path $output
        $passed = ($inventory.exists -and ([string]$inventory.fingerprint -ceq $expectedFingerprint))

        $record.process = $process
        $record.success = $passed
        $record.details = [ordered]@{
            archiveFileName = Get-UnicodeStringEvidence -Text $archiveName
            outputDirectoryName = Get-UnicodeStringEvidence -Text $outputName
            expectedFingerprint = $expectedFingerprint
            actualInventory = $inventory
        }

        $path = Save-RunRecord -Target $Target -Operation $Operation -CaseId $CaseId -Record $record
        Write-Host ('[POC2-ENC] Evidence: {0}' -f $path)
        Write-Host ('[POC2-ENC] Expected fingerprint: {0}' -f $expectedFingerprint)
        Write-Host ('[POC2-ENC] Actual fingerprint  : {0}' -f $inventory.fingerprint)

        if ($process.looksLikeCrash) {
            throw ('LhaForge appears to have crashed: {0}' -f $process.exitCodeHex)
        }
        if (-not $passed) {
            throw ('Path probe failed for case {0}. Stop and review before continuing.' -f $CaseId)
        }
    }

    'compress' {
        if (-not [string]::IsNullOrWhiteSpace($CaseId)) {
            throw 'CaseId is not used for compress.'
        }

        $combinedName = [string]$before.fixture.combinedRootName.text
        $source = Join-Path $fixtureRoot $combinedName
        $output = Join-Path $resultsRoot 'compressed'
        if (Test-Path -LiteralPath $output) {
            Remove-Item -LiteralPath $output -Recurse -Force
        }
        New-Item -ItemType Directory -Path $output -Force | Out-Null

        $archiveName = 'roundtrip-' + (Get-Poc2C1CombinedToken) + '.zip'
        $archive = Join-Path $output $archiveName

        $args = @(
            $cfgArg,
            '/c:zip',
            (Q ('/o:' + $output)),
            (Q ('/f:' + $archiveName)),
            '/method:Deflate',
            '/level:5',
            '/popdir:yes',
            (Q $source)
        )
        $process = Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $zipFile = Get-FileHashEvidence -Path $archive
        $zipInventory = Get-ZipUnicodeInventory -Path $archive
        $passed = ($zipFile.exists -and $zipInventory.exists -and ([string]$zipInventory.fileFingerprint -ceq $expectedArchiveFingerprint))

        $record.process = $process
        $record.success = $passed
        $record.details = [ordered]@{
            sourceDirectoryName = Get-UnicodeStringEvidence -Text $combinedName
            archiveFileName = Get-UnicodeStringEvidence -Text $archiveName
            expectedArchiveFingerprint = $expectedArchiveFingerprint
            archiveFile = $zipFile
            archiveEntries = $zipInventory
        }

        $path = Save-RunRecord -Target $Target -Operation $Operation -Record $record
        Write-Host ('[POC2-ENC] Evidence: {0}' -f $path)
        if ($zipFile.exists) {
            Write-Host ('[POC2-ENC] ZIP SHA-256: {0}' -f $zipFile.sha256)
        }

        if ($process.looksLikeCrash) {
            throw ('LhaForge appears to have crashed: {0}' -f $process.exitCodeHex)
        }
        if (-not $passed) {
            throw 'Unicode compression semantic check failed. Stop and review before continuing.'
        }
    }

    'reextract' {
        if (-not [string]::IsNullOrWhiteSpace($CaseId)) {
            throw 'CaseId is not used for reextract.'
        }

        $archiveName = 'roundtrip-' + (Get-Poc2C1CombinedToken) + '.zip'
        $archive = Join-Path (Join-Path $resultsRoot 'compressed') $archiveName
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw 'Run the compress case before reextract.'
        }

        $outputName = 'reextract-' + (Get-Poc2C1CombinedToken)
        $output = Join-Path $resultsRoot $outputName
        if (Test-Path -LiteralPath $output) {
            Remove-Item -LiteralPath $output -Recurse -Force
        }
        New-Item -ItemType Directory -Path $output -Force | Out-Null

        $args = @(
            $cfgArg,
            '/e',
            (Q ('/o:' + $output)),
            '/mkdir:no',
            (Q $archive)
        )
        $process = Invoke-LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $inventory = Get-UnicodeDirectoryInventory -Path $output
        $passed = ($inventory.exists -and ([string]$inventory.fingerprint -ceq $expectedFingerprint))

        $record.process = $process
        $record.success = $passed
        $record.details = [ordered]@{
            archiveFileName = Get-UnicodeStringEvidence -Text $archiveName
            outputDirectoryName = Get-UnicodeStringEvidence -Text $outputName
            expectedFingerprint = $expectedFingerprint
            actualInventory = $inventory
        }

        $path = Save-RunRecord -Target $Target -Operation $Operation -Record $record
        Write-Host ('[POC2-ENC] Evidence: {0}' -f $path)

        if ($process.looksLikeCrash) {
            throw ('LhaForge appears to have crashed: {0}' -f $process.exitCodeHex)
        }
        if (-not $passed) {
            throw 'Unicode re-extraction fingerprint check failed. Stop and review before continuing.'
        }
    }
}

Write-Host ('[POC2-ENC] {0}/{1}{2} passed.' -f $Target, $Operation, $(if ($CaseId) { '/' + $CaseId } else { '' }))
