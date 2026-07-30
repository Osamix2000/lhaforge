#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repoRoot '.baseline\poc2-ui'
$statePath = Join-Path $root 'external-state-before.json'
$reportPath = Join-Path $root 'isolation-report.json'
$checklistPath = Join-Path $root 'CHECKLIST.md'

function Get-PathState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            name = $Name
            path = $Path
            exists = $false
            kind = $null
            sizeBytes = $null
            sha256 = $null
            lastWriteUtc = $null
        }
    }

    $item = Get-Item -LiteralPath $Path
    $isFile = -not $item.PSIsContainer

    [pscustomobject]@{
        name = $Name
        path = $item.FullName
        exists = $true
        kind = if ($isFile) { 'file' } else { 'directory' }
        sizeBytes = if ($isFile) { $item.Length } else { $null }
        sha256 = if ($isFile) { (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        lastWriteUtc = $item.LastWriteTimeUtc.ToString('o')
    }
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw ('PoC 2 UI snapshot was not found. Run prepare-poc2-ui-regression.ps1 first: {0}' -f $statePath)
}

$beforeDoc = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$results = @()
$allOk = $true

foreach ($before in $beforeDoc.externalPaths) {
    $after = Get-PathState -Name $before.name -Path $before.path

    $same = ($before.exists -eq $after.exists)

    if ($same -and $before.exists) {
        $same = ($before.kind -eq $after.kind)

        if ($same -and $before.kind -eq 'file') {
            $same = (
                $before.sizeBytes -eq $after.sizeBytes -and
                $before.sha256 -eq $after.sha256 -and
                $before.lastWriteUtc -eq $after.lastWriteUtc
            )
        }
        elseif ($same -and $before.kind -eq 'directory') {
            $same = ($before.lastWriteUtc -eq $after.lastWriteUtc)
        }
    }

    if (-not $same) {
        $allOk = $false
    }

    $results += [pscustomobject]@{
        name = $before.name
        path = $before.path
        unchanged = $same
        before = $before
        after = $after
    }

    if ($same) {
        Write-Host ('[OK] External state unchanged: {0}' -f $before.name)
    }
    else {
        Write-Host ('[NG] External state changed: {0}' -f $before.name)
    }
}

$localFiles = @(
    (Join-Path $root 'original\LhaForge.ini'),
    (Join-Path $root 'original\LFCaldix.ini'),
    (Join-Path $root 'modern\LhaForge.ini'),
    (Join-Path $root 'modern\LFCaldix.ini')
)

foreach ($path in $localFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $allOk = $false
        Write-Host ('[NG] Sandbox config missing: {0}' -f $path)
    }
    else {
        Write-Host ('[OK] Sandbox config present: {0}' -f $path)
    }
}

$report = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    isolationPassed = $allOk
    comparisons = $results
    checklist = $checklistPath
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host ('[POC2] Isolation report: {0}' -f $reportPath)
Write-Host ('[POC2] Manual checklist : {0}' -f $checklistPath)

if (-not $allOk) {
    Write-Host '[POC2] Isolation verification failed. Do not proceed to write tests.'
    exit 1
}

Write-Host '[POC2] External AppData / ProgramData configuration state remained unchanged.'
Write-Host '[POC2] PoC 2-A isolation verification passed.'
exit 0
