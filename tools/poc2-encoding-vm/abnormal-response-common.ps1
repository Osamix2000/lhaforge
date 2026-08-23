Set-StrictMode -Version 2.0

function New-Poc2C2AbnormalCase {
	param(
		[Parameter(Mandatory = $true)][string]$Id,
		[Parameter(Mandatory = $true)][string]$FixtureKind,
		[Parameter(Mandatory = $true)][ValidateSet('at', 'dollar')][string]$Directive,
		[Parameter(Mandatory = $true)][string[]]$ArgumentPlan,
		[Parameter(Mandatory = $true)][ValidateSet('asserted', 'observe-only')][string]$ExpectationMode,
		[Nullable[bool]]$ExpectedArchiveExists,
		[ValidateSet('preserved', 'deleted', 'observe')][string]$ExpectedResponsePostState = 'observe',
		[Nullable[int]]$ExpectedExitCode,
		[Nullable[bool]]$DialogExpected,
		[bool]$HighRisk = $false,
		[ValidateSet('none', 'security-change-required')][string]$SecurityDisposition = 'none',
		[Parameter(Mandatory = $true)][string]$SourceRationale
	)

	return [pscustomobject]@{
		id = $Id
		fixtureKind = $FixtureKind
		directive = $Directive
		argumentPlan = @($ArgumentPlan)
		expectation = [pscustomobject]@{
			mode = $ExpectationMode
			archiveExists = $ExpectedArchiveExists
			responsePostState = $ExpectedResponsePostState
			exitCode = $ExpectedExitCode
			dialogExpected = $DialogExpected
			highRisk = $HighRisk
			securityDisposition = $SecurityDisposition
			sourceRationale = $SourceRationale
		}
	}
}

function Get-Poc2C2AbnormalCases {
	return @(
		(New-Poc2C2AbnormalCase `
			-Id 'invalid-cp-value' `
			-FixtureKind 'valid-ascii' `
			-Directive 'at' `
			-ArgumentPlan @('direct-input', 'cp:invalid-value', 'response:a') `
			-ExpectationMode 'asserted' `
			-ExpectedArchiveExists $false `
			-ExpectedResponsePostState 'preserved' `
			-ExpectedExitCode 0 `
			-DialogExpected $true `
			-SourceRationale 'A valid direct input is placed first so FileList is non-empty and main does not fall through to the configuration dialog. ParseCommandLine then rejects an unsupported /cp:<value> before reading the response file and main returns 0 for PROCESS_INVALID.'),

		(New-Poc2C2AbnormalCase `
			-Id 'invalid-cp-syntax' `
			-FixtureKind 'valid-ascii' `
			-Directive 'at' `
			-ArgumentPlan @('direct-input', 'cp:invalid-syntax', 'response:a') `
			-ExpectationMode 'asserted' `
			-ExpectedArchiveExists $false `
			-ExpectedResponsePostState 'preserved' `
			-ExpectedExitCode 0 `
			-DialogExpected $true `
			-SourceRationale 'A valid direct input is placed first so FileList is non-empty and main does not fall through to the configuration dialog. ParseCommandLine then rejects malformed /cp syntax before reading the response file and main returns 0 for PROCESS_INVALID.'),

		(New-Poc2C2AbnormalCase `
			-Id 'invalid-utf8-at' `
			-FixtureKind 'invalid-utf8-tail' `
			-Directive 'at' `
			-ArgumentPlan @('cp:utf8', 'response:a') `
			-ExpectationMode 'asserted' `
			-ExpectedArchiveExists $false `
			-ExpectedResponsePostState 'preserved' `
			-ExpectedExitCode 0 `
			-DialogExpected $true `
			-SourceRationale 'UTF-8 conversion uses MultiByteToWideChar(CP_UTF8, 0, ...). On supported Windows this replaces invalid sequences instead of failing; the resulting nonexistent path is rejected later. /@ preserves the response file.'),

		(New-Poc2C2AbnormalCase `
			-Id 'invalid-utf8-dollar' `
			-FixtureKind 'invalid-utf8-tail' `
			-Directive 'dollar' `
			-ArgumentPlan @('cp:utf8', 'response:a') `
			-ExpectationMode 'asserted' `
			-ExpectedArchiveExists $false `
			-ExpectedResponsePostState 'deleted' `
			-ExpectedExitCode 0 `
			-DialogExpected $true `
			-SourceRationale 'UTF-8 conversion succeeds with replacement. /$ deletes the response file immediately after a successful response read, before later path validation rejects the nonexistent path.'),

		(New-Poc2C2AbnormalCase `
			-Id 'utf16le-lone-surrogate-at' `
			-FixtureKind 'utf16le-lone-surrogate' `
			-Directive 'at' `
			-ArgumentPlan @('cp:utf16', 'response:a') `
			-ExpectationMode 'asserted' `
			-ExpectedArchiveExists $false `
			-ExpectedResponsePostState 'preserved' `
			-ExpectedExitCode 0 `
			-DialogExpected $true `
			-SourceRationale 'UTF-16LE response conversion does not validate surrogate scalar structure. The malformed path is expected to survive conversion and fail later path validation; /@ preserves the response file.'),

		(New-Poc2C2AbnormalCase `
			-Id 'utf16le-odd-at' `
			-FixtureKind 'utf16le-odd' `
			-Directive 'at' `
			-ArgumentPlan @('cp:utf16', 'response:a') `
			-ExpectationMode 'observe-only' `
			-ExpectedResponsePostState 'observe' `
			-HighRisk $true `
			-SecurityDisposition 'security-change-required' `
			-SourceRationale 'Odd-length UTF-16LE causes the reader to append a WCHAR NUL at an unaligned byte offset. The legacy implementation can expose boundary-sensitive behavior, so the Original result is observational evidence rather than a pre-asserted outcome.'),

		(New-Poc2C2AbnormalCase `
			-Id 'utf16be-odd-at' `
			-FixtureKind 'utf16be-odd' `
			-Directive 'at' `
			-ArgumentPlan @('cp:utf16', 'response:a') `
			-ExpectationMode 'observe-only' `
			-ExpectedResponsePostState 'observe' `
			-HighRisk $true `
			-SecurityDisposition 'security-change-required' `
			-SourceRationale 'Odd-length UTF-16BE also passes an odd byte count through the endian-swap path. The last byte and string termination are boundary-sensitive, so the Original result is observational evidence rather than a pre-asserted outcome.')
	)
}

function Get-Poc2C2AbnormalCase {
	param([Parameter(Mandatory = $true)][string]$CaseId)

	$matches = @(Get-Poc2C2AbnormalCases | Where-Object { $_.id -ceq $CaseId })
	if ($matches.Count -ne 1) {
		throw ('Unknown PoC 2-C2 abnormal case id: {0}' -f $CaseId)
	}
	return $matches[0]
}

function Assert-Poc2C2AbnormalAsciiPath {
	param([Parameter(Mandatory = $true)][string]$Path)

	foreach ($ch in $Path.ToCharArray()) {
		if ([int]$ch -gt 0x7F) {
			throw ('PoC 2-C2 abnormal fixtures require an ASCII-only kit/input path. Non-ASCII path: {0}' -f $Path)
		}
	}
}

function Add-Poc2C2ByteRange {
	param(
		[Parameter(Mandatory = $true)]$List,
		[Parameter(Mandatory = $true)][byte[]]$Bytes
	)

	if ($Bytes.Length -gt 0) {
		$List.AddRange($Bytes)
	}
}

function Get-Poc2C2AbnormalResponseBytes {
	param(
		[Parameter(Mandatory = $true)][string]$FixtureKind,
		[Parameter(Mandatory = $true)][string]$InputPath
	)

	Assert-Poc2C2AbnormalAsciiPath -Path $InputPath

	$ascii = [System.Text.Encoding]::ASCII
	$utf16le = New-Object System.Text.UnicodeEncoding -ArgumentList $false, $false, $true
	$utf16be = New-Object System.Text.UnicodeEncoding -ArgumentList $true, $false, $true
	$bytes = New-Object 'System.Collections.Generic.List[byte]'

	switch ($FixtureKind) {
		'valid-ascii' {
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$ascii.GetBytes(('"{0}"' -f $InputPath) + "`r`n"))
		}
		'invalid-utf8-tail' {
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$ascii.GetBytes('"' + $InputPath))
			$bytes.Add([byte]0xC3)
			$bytes.Add([byte]0x28)
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$ascii.GetBytes('"' + "`r`n"))
		}
		'utf16le-lone-surrogate' {
			$bytes.Add([byte]0xFF)
			$bytes.Add([byte]0xFE)
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$utf16le.GetBytes('"' + $InputPath))
			$bytes.Add([byte]0x00)
			$bytes.Add([byte]0xD8)
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$utf16le.GetBytes('"' + "`r`n"))
		}
		'utf16le-odd' {
			$bytes.Add([byte]0xFF)
			$bytes.Add([byte]0xFE)
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$utf16le.GetBytes(('"{0}"' -f $InputPath) + "`r`n"))
			$bytes.Add([byte]0x41)
		}
		'utf16be-odd' {
			$bytes.Add([byte]0xFE)
			$bytes.Add([byte]0xFF)
			Add-Poc2C2ByteRange -List $bytes -Bytes ([byte[]]$utf16be.GetBytes(('"{0}"' -f $InputPath) + "`r`n"))
			$bytes.Add([byte]0x41)
		}
		default {
			throw ('Unsupported PoC 2-C2 abnormal fixture kind: {0}' -f $FixtureKind)
		}
	}

	[byte[]]$result = $bytes.ToArray()
	Write-Output -NoEnumerate $result
}

function Assert-Poc2C2AbnormalByteGenerator {
	$tests = @(
		[pscustomobject]@{
			name = 'valid-ascii'
			fixtureKind = 'valid-ascii'
			expectedHex = '22433A5C41220D0A'
		},
		[pscustomobject]@{
			name = 'invalid-utf8-tail'
			fixtureKind = 'invalid-utf8-tail'
			expectedHex = '22433A5C41C328220D0A'
		},
		[pscustomobject]@{
			name = 'utf16le-lone-surrogate'
			fixtureKind = 'utf16le-lone-surrogate'
			expectedHex = 'FFFE220043003A005C00410000D822000D000A00'
		},
		[pscustomobject]@{
			name = 'utf16le-odd'
			fixtureKind = 'utf16le-odd'
			expectedHex = 'FFFE220043003A005C00410022000D000A0041'
		},
		[pscustomobject]@{
			name = 'utf16be-odd'
			fixtureKind = 'utf16be-odd'
			expectedHex = 'FEFF00220043003A005C00410022000D000A41'
		}
	)

	foreach ($test in $tests) {
		[byte[]]$actual = Get-Poc2C2AbnormalResponseBytes -FixtureKind $test.fixtureKind -InputPath 'C:\A'
		$actualHex = ([System.BitConverter]::ToString($actual)).Replace('-', '')
		if ($actualHex -cne [string]$test.expectedHex) {
			throw ('PoC 2-C2 abnormal byte generator mismatch for {0}. Expected {1}, actual {2}.' -f $test.name, $test.expectedHex, $actualHex)
		}
	}

	foreach ($kind in @('utf16le-odd', 'utf16be-odd')) {
		[byte[]]$odd = Get-Poc2C2AbnormalResponseBytes -FixtureKind $kind -InputPath 'C:\A'
		if (($odd.Length % 2) -ne 1) {
			throw ('PoC 2-C2 abnormal fixture is not odd-length as required: {0}.' -f $kind)
		}
	}
}

function Assert-Poc2C2AbnormalRuntime {
	param(
		[Parameter(Mandatory = $true)]$ExpectedRuntime,
		[Parameter(Mandatory = $true)][string]$KitRoot
	)

	if (Test-IsElevated) {
		throw 'Run PoC 2-C2 abnormal commands from a non-elevated Windows PowerShell session.'
	}

	$driveRoot = [System.IO.Path]::GetPathRoot($KitRoot)
	$drive = New-Object System.IO.DriveInfo($driveRoot)
	if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
		throw ('VM kit must remain on a local fixed disk. Current drive type: {0}' -f $drive.DriveType)
	}

	Assert-Poc2C2AbnormalAsciiPath -Path $KitRoot

	$current = Get-Poc2C2RuntimeEvidence
	$currentVersion = [version]$current.powerShellVersion
	if (
		[string]$current.psEdition -cne 'Desktop' -or
		$currentVersion.Major -ne 5 -or
		$currentVersion.Minor -ne 1
	) {
		throw ('PoC 2-C2 abnormal regression requires Windows PowerShell 5.1 exactly. Current runtime: PowerShell {0}, PSEdition {1}.' -f $current.powerShellVersion, $current.psEdition)
	}
	if ([int]$current.defaultEncodingCodePage -ne 932) {
		throw ('PoC 2-C2 abnormal regression requires ANSI code page 932. Current code page: {0}.' -f $current.defaultEncodingCodePage)
	}

	foreach ($name in @('psEdition', 'defaultEncodingCodePage', 'currentCulture', 'currentUICulture')) {
		if ([string]$current.$name -cne [string]$ExpectedRuntime.$name) {
			throw ('PoC 2-C2 abnormal runtime drift detected for {0}. Expected {1}, current {2}.' -f $name, $ExpectedRuntime.$name, $current.$name)
		}
	}

	$expectedVersion = [version]$ExpectedRuntime.powerShellVersion
	if (
		$currentVersion.Major -ne $expectedVersion.Major -or
		$currentVersion.Minor -ne $expectedVersion.Minor -or
		$currentVersion.Build -ne $expectedVersion.Build -or
		$currentVersion.Revision -ne $expectedVersion.Revision
	) {
		throw ('PoC 2-C2 abnormal PowerShell version drift detected. Expected {0}, current {1}.' -f $ExpectedRuntime.powerShellVersion, $current.powerShellVersion)
	}

	return $current
}

function Get-Poc2C2AbnormalZipContentInventory {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		return [pscustomobject]@{
			path = $Path
			exists = $false
			files = @()
			fingerprint = $null
			parseStatus = 'absent'
			parseError = $null
		}
	}

	try {
		$inventory = Get-Poc2C2ZipContentInventory -Path $Path
		return [pscustomobject]@{
			path = [string]$inventory.path
			exists = [bool]$inventory.exists
			files = @($inventory.files)
			fingerprint = $inventory.fingerprint
			parseStatus = 'parsed'
			parseError = $null
		}
	}
	catch {
		return [pscustomobject]@{
			path = (Get-Item -LiteralPath $Path).FullName
			exists = $true
			files = @()
			fingerprint = $null
			parseStatus = 'error'
			parseError = [string]$_.Exception.Message
		}
	}
}

function Get-Poc2C2AbnormalRunRecordRoot {
	param([Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target)

	return (Join-Path (Get-TargetRoot -Target $Target) 'response-abnormal-results\run-records')
}

function Get-Poc2C2AbnormalRunRecordPath {
	param(
		[Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
		[Parameter(Mandatory = $true)][string]$CaseId
	)

	return (Join-Path (Get-Poc2C2AbnormalRunRecordRoot -Target $Target) ('response-abnormal-' + $CaseId + '.json'))
}

function Save-Poc2C2AbnormalRunRecord {
	param(
		[Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
		[Parameter(Mandatory = $true)][string]$CaseId,
		[Parameter(Mandatory = $true)]$Record
	)

	$root = Get-Poc2C2AbnormalRunRecordRoot -Target $Target
	New-Item -ItemType Directory -Path $root -Force | Out-Null
	$path = Get-Poc2C2AbnormalRunRecordPath -Target $Target -CaseId $CaseId
	Write-JsonUtf8NoBom -Value $Record -Path $path -Depth 28
	return $path
}

function Get-Poc2C2AbnormalCaseEvidence {
	param(
		[Parameter(Mandatory = $true)]$State,
		[Parameter(Mandatory = $true)][string]$CaseId
	)

	$matches = @($State.fixture.cases | Where-Object { $_.id -ceq $CaseId })
	if ($matches.Count -ne 1) {
		throw ('Expected one initialized abnormal C2 case for {0}, found {1}.' -f $CaseId, $matches.Count)
	}
	return $matches[0]
}

function New-Poc2C2AbnormalFixture {
	param([Parameter(Mandatory = $true)][string]$Root)

	if (Test-Path -LiteralPath $Root) {
		Remove-Item -LiteralPath $Root -Recurse -Force
	}
	New-Item -ItemType Directory -Path $Root -Force | Out-Null

	$sourceRoot = Join-Path $Root 'response input'
	$templateRoot = Join-Path $Root 'templates'
	New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
	New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null

	Assert-Poc2C2AbnormalAsciiPath -Path $Root

	$inputPath = Join-Path $sourceRoot 'abnormal-input.txt'
	[System.IO.File]::WriteAllText(
		$inputPath,
		"case=abnormal`r`npayload=response-file-abnormal-regression`r`n",
		[System.Text.Encoding]::ASCII
	)
	$inputEvidence = Get-FileHashEvidence -Path $inputPath

	$caseEvidence = @()
	foreach ($case in Get-Poc2C2AbnormalCases) {
		$caseRoot = Join-Path $templateRoot $case.id
		New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null

		$templatePath = Join-Path $caseRoot 'a.rsp'
		[byte[]]$raw = Get-Poc2C2AbnormalResponseBytes -FixtureKind $case.fixtureKind -InputPath $inputPath
		[System.IO.File]::WriteAllBytes($templatePath, $raw)

		$caseEvidence += [pscustomobject]@{
			id = $case.id
			fixtureKind = $case.fixtureKind
			directive = $case.directive
			argumentPlan = @($case.argumentPlan)
			expectation = $case.expectation
			responseFile = [pscustomobject]@{
				key = 'a'
				template = Get-Poc2C2RawFileEvidence -Path $templatePath
			}
		}
	}

	return [pscustomobject]@{
		root = $Root
		sourceRoot = $sourceRoot
		input = $inputEvidence
		cases = @($caseEvidence)
	}
}

function Invoke-Poc2C2AbnormalLhaForge {
	param(
		[Parameter(Mandatory = $true)][string]$Exe,
		[Parameter(Mandatory = $true)][string]$WorkingDirectory,
		[Parameter(Mandatory = $true)][string[]]$Arguments,
		[Parameter(Mandatory = $true)][ValidateRange(10, 600)][int]$TimeoutSeconds
	)

	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $Exe
	$psi.WorkingDirectory = $WorkingDirectory
	$psi.UseShellExecute = $false
	$psi.Arguments = ($Arguments -join ' ')

	Write-Host ('[POC2-RSP-ABN] Launch: {0} {1}' -f $Exe, $psi.Arguments)
	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	$process = [System.Diagnostics.Process]::Start($psi)
	$timedOut = $false
	$exitCode = $null
	try {
		if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
			$timedOut = $true
			try {
				$process.Kill()
				$process.WaitForExit()
			}
			catch {
				Write-Warning ('Could not terminate timed-out LhaForge process cleanly: {0}' -f $_.Exception.Message)
			}
		}
		if (-not $timedOut) {
			$exitCode = [int]$process.ExitCode
		}
	}
	finally {
		$stopwatch.Stop()
		$process.Dispose()
	}

	$exitHex = if ($null -eq $exitCode) { $null } else { Convert-ExitCodeToHex -ExitCode $exitCode }
	$looksLikeCrash = if ($null -eq $exitCode) { $false } else { Test-ExitLooksLikeCrash -ExitCode $exitCode }

	Write-Host ('[POC2-RSP-ABN] Timed out        : {0}' -f $timedOut)
	Write-Host ('[POC2-RSP-ABN] Process exit code: {0} ({1})' -f $(if ($null -eq $exitCode) { '<none>' } else { $exitCode }), $(if ($null -eq $exitHex) { '<none>' } else { $exitHex }))

	return [pscustomobject]@{
		exitCode = $exitCode
		exitCodeHex = $exitHex
		elapsedMs = [Int64]$stopwatch.ElapsedMilliseconds
		timedOut = $timedOut
		looksLikeCrash = $looksLikeCrash
	}
}

function Read-Poc2C2DialogObservation {
	param([Parameter(Mandatory = $true)][string]$Prompt)

	while ($true) {
		$value = (Read-Host ($Prompt + ' [Y/N/U]')).Trim().ToLowerInvariant()
		switch ($value) {
			'y' { return 'yes' }
			'yes' { return 'yes' }
			'n' { return 'no' }
			'no' { return 'no' }
			'u' { return 'unknown' }
			'unknown' { return 'unknown' }
			default { Write-Host 'Enter Y, N, or U.' }
		}
	}
}

function Get-Poc2C2AbnormalBehaviorSignature {
	param(
		[Parameter(Mandatory = $true)]$Process,
		[Parameter(Mandatory = $true)]$ArchiveFile,
		[Parameter(Mandatory = $true)]$ArchiveInventory,
		[Parameter(Mandatory = $true)]$ResponseAfter
	)

	# Keep the signature machine-observable and semantic. Whole ZIP bytes and
	# manual dialog confirmation are recorded separately and do not decide MATCH.
	$parts = @(
		('timeout={0}' -f [bool]$Process.timedOut),
		('crash={0}' -f [bool]$Process.looksLikeCrash),
		('exit={0}' -f $(if ($null -eq $Process.exitCodeHex) { '<null>' } else { [string]$Process.exitCodeHex })),
		('archiveExists={0}' -f [bool]$ArchiveFile.exists),
		('archiveParseStatus={0}' -f [string]$ArchiveInventory.parseStatus),
		('archiveFingerprint={0}' -f $(if ($null -eq $ArchiveInventory.fingerprint) { '<null>' } else { [string]$ArchiveInventory.fingerprint })),
		('responseExists={0}' -f [bool]$ResponseAfter.exists),
		('responseSha={0}' -f $(if ($null -eq $ResponseAfter.sha256) { '<null>' } else { [string]$ResponseAfter.sha256 }))
	)
	return (Get-StringSha256 -Text ($parts -join "`n"))
}

function Test-Poc2C2TempZipStateEqual {
	param(
		[Parameter(Mandatory = $true)]$Left,
		[Parameter(Mandatory = $true)]$Right
	)

	$leftItems = @($Left)
	$rightItems = @($Right)
	if ($leftItems.Count -ne $rightItems.Count) {
		return $false
	}

	for ($i = 0; $i -lt $leftItems.Count; $i++) {
		$a = $leftItems[$i]
		$b = $rightItems[$i]
		if (
			[string]$a.path -cne [string]$b.path -or
			[Int64]$a.sizeBytes -ne [Int64]$b.sizeBytes -or
			[string]$a.sha256 -cne [string]$b.sha256
		) {
			return $false
		}
	}
	return $true
}

function Test-Poc2C2AbnormalExpectation {
	param(
		[Parameter(Mandatory = $true)]$Case,
		[Parameter(Mandatory = $true)]$Process,
		[Parameter(Mandatory = $true)]$ArchiveFile,
		[Parameter(Mandatory = $true)]$ResponseBefore,
		[Parameter(Mandatory = $true)]$ResponseAfter,
		[Parameter(Mandatory = $true)][string]$DialogObservation
	)

	if ([string]$Case.expectation.mode -ceq 'observe-only') {
		return [pscustomobject]@{
			asserted = $false
			matched = $null
			issues = @()
		}
	}

	$issues = New-Object System.Collections.Generic.List[string]

	if ([bool]$Process.timedOut) {
		[void]$issues.Add('Process timed out.')
	}
	if ([bool]$Process.looksLikeCrash) {
		[void]$issues.Add(('Process looks like a crash: {0}' -f $Process.exitCodeHex))
	}
	if ($null -eq $Process.exitCode -or [int]$Process.exitCode -ne [int]$Case.expectation.exitCode) {
		[void]$issues.Add(('Exit code differs from source expectation. Expected {0}, actual {1}.' -f $Case.expectation.exitCode, $Process.exitCode))
	}
	if ([bool]$ArchiveFile.exists -ne [bool]$Case.expectation.archiveExists) {
		[void]$issues.Add(('Archive existence differs from source expectation. Expected {0}, actual {1}.' -f $Case.expectation.archiveExists, $ArchiveFile.exists))
	}

	switch ([string]$Case.expectation.responsePostState) {
		'preserved' {
			if (-not [bool]$ResponseAfter.exists) {
				[void]$issues.Add('Response file was expected to be preserved but is missing.')
			}
			elseif (
				[string]$ResponseAfter.sha256 -cne [string]$ResponseBefore.sha256 -or
				[Int64]$ResponseAfter.sizeBytes -ne [Int64]$ResponseBefore.sizeBytes
			) {
				[void]$issues.Add('Response file was expected to be preserved byte-identically but its raw identity changed.')
			}
		}
		'deleted' {
			if ([bool]$ResponseAfter.exists) {
				[void]$issues.Add('Response file was expected to be deleted but still exists.')
			}
		}
	}

	if ([bool]$Case.expectation.dialogExpected -and $DialogObservation -cne 'yes') {
		[void]$issues.Add(('Expected error dialog was not positively confirmed. Observation: {0}.' -f $DialogObservation))
	}

	return [pscustomobject]@{
		asserted = $true
		matched = ($issues.Count -eq 0)
		issues = @($issues)
	}
}
