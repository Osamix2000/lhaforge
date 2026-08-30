#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('original', 'modern')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateSet('list', 'test', 'extract')]
    [string]$Operation,

    [Parameter(Mandatory = $true)]
    [string]$CaseId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'c3-common.ps1')

function Q {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-C3LhaForge {
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

    Write-Host ('[POC2-C3] Launch: {0} {1}' -f $Exe, $psi.Arguments)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    $sw.Stop()

    $exitCode = [int]$p.ExitCode
    return [pscustomobject]@{
        exitCode = $exitCode
        exitCodeHex = Convert-ExitCodeToHex -ExitCode $exitCode
        elapsedMs = [Int64]$sw.ElapsedMilliseconds
        looksLikeCrash = Test-ExitLooksLikeCrash -ExitCode $exitCode
    }
}

function Read-C3Choice {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string[]]$Allowed
    )
    while ($true) {
        $answer = (Read-Host $Prompt).Trim().ToLowerInvariant()
        if ($Allowed -contains $answer) { return $answer }
        Write-Host ('Allowed: {0}' -f ($Allowed -join ', '))
    }
}

$kitRoot = Get-KitRoot
$targetRoot = Get-TargetRoot -Target $Target
$exe = Join-Path $targetRoot 'LhaForge.exe'
$config = Join-Path $targetRoot 'LhaForge.ini'
$statePath = Join-Path $kitRoot 'evidence-c3\state-before-c3.json'

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw 'Run initialize-c3-regression.ps1 first.'
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw ('LhaForge.exe was not found: {0}' -f $exe)
}

$fixtureIdentity = Assert-C3FixtureIdentity -CaseId $CaseId
$fixtureCase = Get-C3FixtureCase -CaseId $CaseId
$fixturePath = [string]$fixtureIdentity.path
$cfgArg = Q ('/cfg:' + $config)

$record = [ordered]@{
    schemaVersion = 1
    target = $Target
    operation = $Operation
    caseId = $CaseId
    behaviorClass = [string]$fixtureIdentity.behaviorClass
    archiveSha256 = [string]$fixtureIdentity.sha256
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    process = $null
    observationKey = $null
    observationNote = $null
    details = $null
    externalAfter = $null
}

$stateBefore = Read-JsonUtf8 -Path $statePath

function Set-C3OptionalObservationNote {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    $note = Read-Host $Prompt
    if (-not [string]::IsNullOrWhiteSpace($note)) {
        $Record.observationNote = $note
    }
}

function Complete-C3RunRecord {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)]$Process
    )

    $externalAfter = Get-ExternalState
    $Record.externalAfter = $externalAfter

    $path = Save-C3RunRecord -Target $Target -Operation $Operation -CaseId $CaseId -Record $Record
    Write-Host ('[POC2-C3] Evidence: {0}' -f $path)

    if ($Process.looksLikeCrash) {
        throw ('LhaForge appears to have crashed: {0}' -f $Process.exitCodeHex)
    }

    if (-not (Test-ExternalInventoryEqual -Left $stateBefore.external -Right $externalAfter)) {
        throw ('External AppData/ProgramData state changed after {0}/{1}/{2}. Stop and preserve evidence.' -f $Target, $Operation, $CaseId)
    }
}

switch ($Operation) {
    'list' {
        $args = @($cfgArg, '/l', (Q $fixturePath))
        $process = Invoke-C3LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $record.process = $process

        Write-Host ''
        Write-Host ('[POC2-C3] Case: {0}  Class: {1}' -f $CaseId, $fixtureIdentity.behaviorClass)

        $entries = @($fixtureCase.entries)
        $candidates = @(Get-C3NameCandidates -FixtureCase $fixtureCase)
        if ($entries.Count -eq 1 -and $candidates.Count -gt 0) {
            $allowed = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $candidates.Count; $i++) {
                $n = ($i + 1).ToString()
                [void]$allowed.Add($n)
                Write-Host ('  [{0}] {1}' -f $n, $candidates[$i].key)
                Write-Host ('      text       : {0}' -f $candidates[$i].text)
                Write-Host ('      code points: {0}' -f (($candidates[$i].codePoints) -join ' '))
            }
            [void]$allowed.Add('e')
            [void]$allowed.Add('o')
            Write-Host '  [e] Archive/list error or no usable name'
            Write-Host '  [o] Other result'
            $choice = Read-C3Choice -Prompt 'Which result matched the List window?' -Allowed ([string[]]$allowed)

            if ($choice -match '^\d+$') {
                $selected = $candidates[[int]$choice - 1]
                $record.observationKey = [string]$selected.key
                $record.details = [ordered]@{
                    selected = $selected
                    candidates = @($candidates)
                }
            }
            elseif ($choice -ceq 'e') {
                $record.observationKey = 'error'
                $record.details = [ordered]@{ candidates = @($candidates) }
                Set-C3OptionalObservationNote -Record $record -Prompt 'Optional error/warning text or observation note (Enter to skip)'
            }
            else {
                $record.observationKey = 'other'
                $record.details = [ordered]@{ candidates = @($candidates) }
                Set-C3OptionalObservationNote -Record $record -Prompt 'Describe the unexpected List result (Enter to skip)'
            }
        }
        else {
            Write-Host 'Expected semantic names:'
            foreach ($entry in $entries) {
                if (-not [string]::IsNullOrEmpty([string]$entry.semanticName)) {
                    Write-Host ('  {0}' -f $entry.semanticName)
                    Write-Host ('    {0}' -f ((@($entry.semanticCodePoints)) -join ' '))
                }
            }
            $choice = Read-C3Choice -Prompt 'List observation [m=matches shown names, e=error, o=other]' -Allowed @('m', 'e', 'o')
            $record.observationKey = switch ($choice) {
                'm' { 'semantic-match' }
                'e' { 'error' }
                default { 'other' }
            }
            $record.details = [ordered]@{ entryCount = $entries.Count }

            if ($choice -ceq 'e') {
                Set-C3OptionalObservationNote -Record $record -Prompt 'Optional error/warning text or observation note (Enter to skip)'
            }
            elseif ($choice -ceq 'o') {
                Set-C3OptionalObservationNote -Record $record -Prompt 'Describe the unexpected List result (Enter to skip)'
            }
        }

        Complete-C3RunRecord -Record $record -Process $process
    }

    'test' {
        $args = @($cfgArg, '/t', (Q $fixturePath))
        $process = Invoke-C3LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $record.process = $process

        $choice = Read-C3Choice -Prompt 'Archive test observation [s=success, e=error/warning, o=other]' -Allowed @('s', 'e', 'o')
        $record.observationKey = switch ($choice) {
            's' { 'success' }
            'e' { 'error-or-warning' }
            default { 'other' }
        }
        $record.details = [ordered]@{}

        if ($choice -ceq 'e') {
            Set-C3OptionalObservationNote -Record $record -Prompt 'Optional test error/warning text (Enter to skip)'
        }
        elseif ($choice -ceq 'o') {
            Set-C3OptionalObservationNote -Record $record -Prompt 'Describe the unexpected Test result (Enter to skip)'
        }

        Complete-C3RunRecord -Record $record -Process $process
    }

    'extract' {
        $outputRoot = Join-Path (Join-Path $targetRoot 'results\c3-extract') $CaseId
        if (Test-Path -LiteralPath $outputRoot) {
            Remove-Item -LiteralPath $outputRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

        $args = @(
            $cfgArg,
            '/e',
            (Q ('/o:' + $outputRoot)),
            '/mkdir:no',
            (Q $fixturePath)
        )
        $process = Invoke-C3LhaForge -Exe $exe -WorkingDirectory $targetRoot -Arguments $args
        $inventory = Get-C3DirectoryInventory -Path $outputRoot
        $semanticMatch = Test-C3InventoryMatchesSemantic -Inventory $inventory -FixtureCase $fixtureCase

        $choice = Read-C3Choice -Prompt 'Extraction UI observation [n=no error/warning, e=error/warning, o=other]' -Allowed @('n', 'e', 'o')
        $record.observationKey = switch ($choice) {
            'n' { 'no-error-ui' }
            'e' { 'error-or-warning-ui' }
            default { 'other' }
        }
        $record.process = $process
        $record.details = [ordered]@{
            outputRoot = $outputRoot
            inventory = $inventory
            semanticMatch = $semanticMatch
        }

        if ($choice -ceq 'e') {
            Set-C3OptionalObservationNote -Record $record -Prompt 'Optional extraction error/warning text (Enter to skip)'
        }
        elseif ($choice -ceq 'o') {
            Set-C3OptionalObservationNote -Record $record -Prompt 'Describe the unexpected Extract result (Enter to skip)'
        }

        Complete-C3RunRecord -Record $record -Process $process
        Write-Host ('[POC2-C3] Extract fingerprint: {0}' -f $inventory.fingerprint)
        if ($null -ne $semanticMatch) {
            Write-Host ('[POC2-C3] Matches declared semantic inventory: {0}' -f $semanticMatch)
        }
    }
}

Write-Host ('[POC2-C3] {0}/{1}/{2} recorded.' -f $Target, $Operation, $CaseId)
