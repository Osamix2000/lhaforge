#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('original', 'modern')]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'c3-common.ps1')

$runScript = Join-Path $PSScriptRoot 'run-c3-case.ps1'

foreach ($case in Get-Poc2C3FrozenCases) {
    Write-Host ''
    Write-Host ('========== {0} / {1} ==========' -f $Target, $case.id)

    foreach ($op in @('list', 'test', 'extract')) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runScript -Target $Target -Operation $op -CaseId $case.id
        if ($LASTEXITCODE -ne 0) {
            throw ('C3 runner stopped at {0}/{1}/{2} with exit code {3}.' -f $Target, $case.id, $op, $LASTEXITCODE)
        }
    }
}

Write-Host ''
Write-Host ('[POC2-C3] Target run complete: {0}' -f $Target)
Write-Host ('[POC2-C3] Next: capture-c3-result.ps1 -Target {0}' -f $Target)
