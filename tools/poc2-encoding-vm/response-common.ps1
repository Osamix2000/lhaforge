Set-StrictMode -Version 2.0

function Get-Poc2C2InputDefinitions {
	return @(
		[pscustomobject]@{ id = 'ascii'; codePoints = @(0x41, 0x53, 0x43, 0x49, 0x49) },
		[pscustomobject]@{ id = 'japanese'; codePoints = @(0x65E5, 0x672C, 0x8A9E) },
		[pscustomobject]@{ id = 'emoji'; codePoints = @(0x1F600) },
		[pscustomobject]@{ id = 'supplementary'; codePoints = @(0x2000B) },
		[pscustomobject]@{ id = 'combining'; codePoints = @(0x41, 0x030A) },
		[pscustomobject]@{ id = 'nfc'; codePoints = @(0x00E9) },
		[pscustomobject]@{ id = 'nfd'; codePoints = @(0x65, 0x0301) }
	)
}

function Get-Poc2C2InputToken {
	param([Parameter(Mandatory = $true)]$InputDefinition)

	return (New-StringFromCodePoints -CodePoints ([int[]]$InputDefinition.codePoints))
}

function Get-Poc2C2InputFileName {
	param([Parameter(Mandatory = $true)]$InputDefinition)

	return ('response-input-{0}-{1}.txt' -f $InputDefinition.id, (Get-Poc2C2InputToken -InputDefinition $InputDefinition))
}

function New-Poc2C2ResponseSpec {
	param(
		[Parameter(Mandatory = $true)][string]$Key,
		[Parameter(Mandatory = $true)][ValidateSet('cp932', 'utf8', 'utf16le', 'utf16be')][string]$Encoding,
		[Parameter(Mandatory = $true)][bool]$Bom,
		[Parameter(Mandatory = $true)][ValidateSet('crlf', 'lf', 'cr')][string]$Newline,
		[Parameter(Mandatory = $true)][string[]]$InputIds,
		[Parameter(Mandatory = $true)][ValidateSet('at', 'dollar')][string]$Directive
	)

	return [pscustomobject]@{
		key = $Key
		encoding = $Encoding
		bom = $Bom
		newline = $Newline
		inputIds = @($InputIds)
		directive = $Directive
	}
}

function Get-Poc2C2Cases {
	$legacy = @('ascii', 'japanese')
	$unicodeOnly = @('emoji', 'supplementary', 'combining', 'nfc', 'nfd')
	$all = @('ascii', 'japanese', 'emoji', 'supplementary', 'combining', 'nfc', 'nfd')

	return @(
		[pscustomobject]@{
			id = 'sjis-crlf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'cp932' -Bom $false -Newline 'crlf' -InputIds $legacy -Directive 'at')
			)
			argumentPlan = @('cp:sjis', 'response:a')
			expectedInputIds = @($legacy)
		},
		[pscustomobject]@{
			id = 'utf8-nobom-crlf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf8' -Bom $false -Newline 'crlf' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf8', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'utf8-bom-crlf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf8' -Bom $true -Newline 'crlf' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf8', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'utf16le-bom-crlf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf16le' -Bom $true -Newline 'crlf' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf16', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'utf16be-bom-crlf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf16be' -Bom $true -Newline 'crlf' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf16', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'utf16le-nobom-crlf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf16le' -Bom $false -Newline 'crlf' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf16', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'utf8-nobom-lf'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf8' -Bom $false -Newline 'lf' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf8', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'utf8-nobom-cr'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf8' -Bom $false -Newline 'cr' -InputIds $all -Directive 'at')
			)
			argumentPlan = @('cp:utf8', 'response:a')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'sequence-sjis-then-utf8'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'cp932' -Bom $false -Newline 'crlf' -InputIds $legacy -Directive 'at'),
				(New-Poc2C2ResponseSpec -Key 'b' -Encoding 'utf8' -Bom $false -Newline 'crlf' -InputIds $unicodeOnly -Directive 'at')
			)
			argumentPlan = @('response:a', 'cp:utf8', 'response:b')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'sequence-utf8-reset-sjis'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf8' -Bom $false -Newline 'crlf' -InputIds $unicodeOnly -Directive 'at'),
				(New-Poc2C2ResponseSpec -Key 'b' -Encoding 'cp932' -Bom $false -Newline 'crlf' -InputIds $legacy -Directive 'at')
			)
			argumentPlan = @('cp:utf8', 'response:a', 'cp:reset', 'response:b')
			expectedInputIds = @($all)
		},
		[pscustomobject]@{
			id = 'dollar-delete-utf8'
			responseFiles = @(
				(New-Poc2C2ResponseSpec -Key 'a' -Encoding 'utf8' -Bom $false -Newline 'crlf' -InputIds $all -Directive 'dollar')
			)
			argumentPlan = @('cp:utf8', 'response:a')
			expectedInputIds = @($all)
		}
	)
}

function Get-Poc2C2Case {
	param([Parameter(Mandatory = $true)][string]$CaseId)

	$matches = @(Get-Poc2C2Cases | Where-Object { $_.id -ceq $CaseId })
	if ($matches.Count -ne 1) {
		throw ('Unknown PoC 2-C2 case id: {0}' -f $CaseId)
	}
	return $matches[0]
}

function Get-Poc2C2RuntimeEvidence {
	return [pscustomobject]@{
		powerShellVersion = $PSVersionTable.PSVersion.ToString()
		psEdition = [string]$PSVersionTable.PSEdition
		clrVersion = [Environment]::Version.ToString()
		defaultEncodingCodePage = [int][System.Text.Encoding]::Default.CodePage
		currentCulture = [Globalization.CultureInfo]::CurrentCulture.Name
		currentUICulture = [Globalization.CultureInfo]::CurrentUICulture.Name
		osVersion = [Environment]::OSVersion.VersionString
	}
}

function Get-Poc2C2Cp932Encoding {
	$encoderFallback = New-Object System.Text.EncoderExceptionFallback
	$decoderFallback = New-Object System.Text.DecoderExceptionFallback
	return [System.Text.Encoding]::GetEncoding(932, $encoderFallback, $decoderFallback)
}

function Get-Poc2C2EncodedBytes {
	param(
		[Parameter(Mandatory = $true)][string]$Text,
		[Parameter(Mandatory = $true)][ValidateSet('cp932', 'utf8', 'utf16le', 'utf16be')][string]$Encoding,
		[Parameter(Mandatory = $true)][bool]$Bom
	)

	switch ($Encoding) {
		'cp932' {
			if ($Bom) { throw 'CP932 response fixtures do not use a BOM.' }
			$encoder = Get-Poc2C2Cp932Encoding
		}
		'utf8' {
			$encoder = New-Object System.Text.UTF8Encoding($Bom, $true)
		}
		'utf16le' {
			$encoder = New-Object System.Text.UnicodeEncoding -ArgumentList $false, $Bom, $true
		}
		'utf16be' {
			$encoder = New-Object System.Text.UnicodeEncoding -ArgumentList $true, $Bom, $true
		}
		default {
			throw ('Unsupported response encoding: {0}' -f $Encoding)
		}
	}

	[byte[]]$payload = $encoder.GetBytes($Text)
	[byte[]]$preamble = @()
	if ($Bom) {
		$preamble = $encoder.GetPreamble()
	}

	[byte[]]$result = New-Object byte[] ($preamble.Length + $payload.Length)
	if ($preamble.Length -gt 0) {
		[Array]::Copy($preamble, 0, $result, 0, $preamble.Length)
	}
	if ($payload.Length -gt 0) {
		[Array]::Copy($payload, 0, $result, $preamble.Length, $payload.Length)
	}

	Write-Output -NoEnumerate $result
}

function Assert-Poc2C2EncodingByteGenerator {
	$tests = @(
		[pscustomobject]@{ name = 'cp932-ascii'; text = 'A'; encoding = 'cp932'; bom = $false; expectedHex = '41' },
		[pscustomobject]@{ name = 'cp932-japanese'; text = (New-StringFromCodePoints -CodePoints @(0x65E5, 0x672C, 0x8A9E)); encoding = 'cp932'; bom = $false; expectedHex = '93FA967B8CEA' },
		[pscustomobject]@{ name = 'utf8-nobom'; text = 'A'; encoding = 'utf8'; bom = $false; expectedHex = '41' },
		[pscustomobject]@{ name = 'utf8-bom'; text = 'A'; encoding = 'utf8'; bom = $true; expectedHex = 'EFBBBF41' },
		[pscustomobject]@{ name = 'utf16le-nobom'; text = 'A'; encoding = 'utf16le'; bom = $false; expectedHex = '4100' },
		[pscustomobject]@{ name = 'utf16le-bom'; text = 'A'; encoding = 'utf16le'; bom = $true; expectedHex = 'FFFE4100' },
		[pscustomobject]@{ name = 'utf16be-bom'; text = 'A'; encoding = 'utf16be'; bom = $true; expectedHex = 'FEFF0041' }
	)

	foreach ($test in $tests) {
		[byte[]]$actual = Get-Poc2C2EncodedBytes `
			-Text $test.text `
			-Encoding $test.encoding `
			-Bom ([bool]$test.bom)

		if ($null -eq $actual) {
			throw ('PoC 2-C2 encoding byte generator returned null: {0}' -f $test.name)
		}

		$actualHex = ([System.BitConverter]::ToString($actual)).Replace('-', '')
		if ($actualHex -cne [string]$test.expectedHex) {
			throw ('PoC 2-C2 encoding byte generator mismatch for {0}. Expected {1}, actual {2}.' -f $test.name, $test.expectedHex, $actualHex)
		}
	}
}

function Write-Poc2C2ResponseFile {
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][string[]]$Lines,
		[Parameter(Mandatory = $true)][ValidateSet('cp932', 'utf8', 'utf16le', 'utf16be')][string]$Encoding,
		[Parameter(Mandatory = $true)][bool]$Bom,
		[Parameter(Mandatory = $true)][ValidateSet('crlf', 'lf', 'cr')][string]$Newline
	)

	switch ($Newline) {
		'crlf' { $separator = "`r`n" }
		'lf' { $separator = "`n" }
		'cr' { $separator = "`r" }
		default { throw ('Unsupported newline: {0}' -f $Newline) }
	}

	$text = (@($Lines) -join $separator) + $separator
	$bytes = Get-Poc2C2EncodedBytes -Text $text -Encoding $Encoding -Bom $Bom
	[System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Get-Poc2C2RawFileEvidence {
	param([Parameter(Mandatory = $true)][string]$Path)

	$file = Get-FileHashEvidence -Path $Path
	if (-not $file.exists) {
		return [pscustomobject]@{
			path = $Path
			exists = $false
			sizeBytes = $null
			sha256 = $null
			firstBytesHex = @()
		}
	}

	$bytes = [System.IO.File]::ReadAllBytes($Path)
	$prefixLength = [Math]::Min(4, $bytes.Length)
	$prefix = @()
	for ($i = 0; $i -lt $prefixLength; $i++) {
		$prefix += ('{0:X2}' -f $bytes[$i])
	}

	return [pscustomobject]@{
		path = $file.path
		exists = $true
		sizeBytes = $file.sizeBytes
		sha256 = $file.sha256
		firstBytesHex = @($prefix)
	}
}

function Get-Poc2C2ExpectedArchiveInventory {
	param(
		[Parameter(Mandatory = $true)]$InputEvidence,
		[Parameter(Mandatory = $true)][string[]]$InputIds
	)

	$files = @()
	foreach ($id in $InputIds) {
		$matches = @($InputEvidence | Where-Object { $_.id -ceq $id })
		if ($matches.Count -ne 1) {
			throw ('Expected exactly one C2 input for id {0}, found {1}.' -f $id, $matches.Count)
		}
		$item = $matches[0]
		$files += [pscustomobject]@{
			id = $id
			fullName = [string]$item.fileName.text
			unicode = $item.fileName
			length = [Int64]$item.sizeBytes
			sha256 = [string]$item.sha256
		}
	}

	$canonical = @()
	foreach ($file in ($files | Sort-Object fullName)) {
		$canonical += ('F|{0}|{1}|{2}' -f (($file.unicode.codePoints) -join ','), $file.length, $file.sha256)
	}

	return [pscustomobject]@{
		files = @($files)
		fingerprint = Get-StringSha256 -Text ($canonical -join "`n")
	}
}

function Get-Poc2C2ZipContentInventory {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		return [pscustomobject]@{
			path = $Path
			exists = $false
			files = @()
			fingerprint = $null
		}
	}

	Add-Type -AssemblyName System.IO.Compression
	Add-Type -AssemblyName System.IO.Compression.FileSystem

	$stream = [System.IO.File]::Open(
		$Path,
		[System.IO.FileMode]::Open,
		[System.IO.FileAccess]::Read,
		[System.IO.FileShare]::Read
	)
	try {
		$zip = New-Object System.IO.Compression.ZipArchive(
			$stream,
			[System.IO.Compression.ZipArchiveMode]::Read,
			$false
		)
		try {
			$files = @()
			foreach ($entry in ($zip.Entries | Sort-Object FullName)) {
				$name = $entry.FullName.Replace('\', '/')
				if ($name.EndsWith('/')) { continue }

				$entryStream = $entry.Open()
				try {
					$sha = [System.Security.Cryptography.SHA256]::Create()
					try {
						$hash = $sha.ComputeHash($entryStream)
						$hashText = ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
					}
					finally {
						$sha.Dispose()
					}
				}
				finally {
					$entryStream.Dispose()
				}

				$files += [pscustomobject]@{
					fullName = $name
					unicode = Get-UnicodeStringEvidence -Text $name
					length = [Int64]$entry.Length
					sha256 = $hashText
				}
			}
		}
		finally {
			$zip.Dispose()
		}
	}
	finally {
		$stream.Dispose()
	}

	$canonical = @()
	foreach ($file in ($files | Sort-Object fullName)) {
		$canonical += ('F|{0}|{1}|{2}' -f (($file.unicode.codePoints) -join ','), $file.length, $file.sha256)
	}

	return [pscustomobject]@{
		path = (Get-Item -LiteralPath $Path).FullName
		exists = $true
		files = @($files)
		fingerprint = Get-StringSha256 -Text ($canonical -join "`n")
	}
}

function New-Poc2C2Fixture {
	param([Parameter(Mandatory = $true)][string]$Root)

	if (Test-Path -LiteralPath $Root) {
		Remove-Item -LiteralPath $Root -Recurse -Force
	}
	New-Item -ItemType Directory -Path $Root -Force | Out-Null

	$sourceRoot = Join-Path $Root 'response input'
	$templateRoot = Join-Path $Root 'templates'
	New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
	New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null

	$inputs = @()
	foreach ($definition in Get-Poc2C2InputDefinitions) {
		$token = Get-Poc2C2InputToken -InputDefinition $definition
		$fileName = Get-Poc2C2InputFileName -InputDefinition $definition
		$filePath = Join-Path $sourceRoot $fileName
		[System.IO.File]::WriteAllText(
			$filePath,
			('case={0}' -f $definition.id) + "`r`npayload=response-file-regression`r`n",
			[System.Text.Encoding]::ASCII
		)
		$file = Get-Item -LiteralPath $filePath
		$inputs += [pscustomobject]@{
			id = $definition.id
			token = Get-UnicodeStringEvidence -Text $token
			fileName = Get-UnicodeStringEvidence -Text $fileName
			fullPath = $file.FullName
			sizeBytes = [Int64]$file.Length
			sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
		}
	}

	$caseEvidence = @()
	foreach ($case in Get-Poc2C2Cases) {
		$caseTemplateRoot = Join-Path $templateRoot $case.id
		New-Item -ItemType Directory -Path $caseTemplateRoot -Force | Out-Null

		$responseEvidence = @()
		foreach ($spec in $case.responseFiles) {
			$lines = @()
			foreach ($id in $spec.inputIds) {
				$matches = @($inputs | Where-Object { $_.id -ceq $id })
				if ($matches.Count -ne 1) {
					throw ('Could not resolve C2 input id {0} for case {1}.' -f $id, $case.id)
				}
				$lines += ('"' + [string]$matches[0].fullPath + '"')
			}

			$templatePath = Join-Path $caseTemplateRoot ($spec.key + '.rsp')
			Write-Poc2C2ResponseFile `
				-Path $templatePath `
				-Lines $lines `
				-Encoding $spec.encoding `
				-Bom ([bool]$spec.bom) `
				-Newline $spec.newline

			$responseEvidence += [pscustomobject]@{
				key = $spec.key
				encoding = $spec.encoding
				bom = [bool]$spec.bom
				newline = $spec.newline
				inputIds = @($spec.inputIds)
				directive = $spec.directive
				template = Get-Poc2C2RawFileEvidence -Path $templatePath
			}
		}

		$expected = Get-Poc2C2ExpectedArchiveInventory -InputEvidence $inputs -InputIds ([string[]]$case.expectedInputIds)
		$caseEvidence += [pscustomobject]@{
			id = $case.id
			argumentPlan = @($case.argumentPlan)
			expectedInputIds = @($case.expectedInputIds)
			expectedArchive = $expected
			responseFiles = @($responseEvidence)
		}
	}

	return [pscustomobject]@{
		root = $Root
		sourceRoot = $sourceRoot
		inputs = @($inputs)
		cases = @($caseEvidence)
	}
}

function Get-Poc2C2RunRecordRoot {
	param([Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target)

	return (Join-Path (Get-TargetRoot -Target $Target) 'response-results\run-records')
}

function Get-Poc2C2RunRecordPath {
	param(
		[Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
		[Parameter(Mandatory = $true)][string]$CaseId
	)

	return (Join-Path (Get-Poc2C2RunRecordRoot -Target $Target) ('response-' + $CaseId + '.json'))
}

function Save-Poc2C2RunRecord {
	param(
		[Parameter(Mandatory = $true)][ValidateSet('original', 'modern')][string]$Target,
		[Parameter(Mandatory = $true)][string]$CaseId,
		[Parameter(Mandatory = $true)]$Record
	)

	$root = Get-Poc2C2RunRecordRoot -Target $Target
	New-Item -ItemType Directory -Path $root -Force | Out-Null
	$path = Get-Poc2C2RunRecordPath -Target $Target -CaseId $CaseId
	Write-JsonUtf8NoBom -Value $Record -Path $path -Depth 24
	return $path
}

function Quote-Poc2C2Argument {
	param([Parameter(Mandatory = $true)][string]$Value)

	return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-Poc2C2LhaForge {
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

	Write-Host ('[POC2-RSP] Launch: {0} {1}' -f $Exe, $psi.Arguments)
	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	$process = [System.Diagnostics.Process]::Start($psi)
	try {
		$process.WaitForExit()
		$stopwatch.Stop()
		$exitCode = [int]$process.ExitCode
	}
	finally {
		if ($stopwatch.IsRunning) { $stopwatch.Stop() }
		$process.Dispose()
	}

	$exitHex = Convert-ExitCodeToHex -ExitCode $exitCode
	Write-Host ('[POC2-RSP] Process exit code: {0} ({1})' -f $exitCode, $exitHex)

	return [pscustomobject]@{
		exitCode = $exitCode
		exitCodeHex = $exitHex
		elapsedMs = [Int64]$stopwatch.ElapsedMilliseconds
		looksLikeCrash = Test-ExitLooksLikeCrash -ExitCode $exitCode
	}
}

function Get-Poc2C2CaseEvidence {
	param(
		[Parameter(Mandatory = $true)]$State,
		[Parameter(Mandatory = $true)][string]$CaseId
	)

	$matches = @($State.fixture.cases | Where-Object { $_.id -ceq $CaseId })
	if ($matches.Count -ne 1) {
		throw ('Expected one initialized C2 case for {0}, found {1}.' -f $CaseId, $matches.Count)
	}
	return $matches[0]
}
