# LhaForge v1.7.0 PoC 2-C3 Archive Entry Name Metadata

- Status: Host fixture gate complete / Runtime comparison pending
- Host validation date: 2026-08-30
- Baseline target: LhaForge v1.6.7 original binary
- Modern comparison target: `develop-v1.7.0` x86 Release
- Historical ZIP backend: `7-ZIP32.DLL` 9.22.0.2 x86
- Historical backend SHA-256: `A82D2B10960F9EBAF5B9D56E2F495C72C22F5DE542740D585AB14CB0B291999C`
- Repository HEAD before adding C3 host tooling: `745305d4867fe3ae0a134e3198c5b6ae0d619e21`
- Purpose: ZIP Entry NameのRaw MetadataをDeterministic Fixtureとして固定し、Original / Modern x86のHistorical Behaviorを同一条件で比較できる状態を作る。

Related documents:

- `regression-encoding.md`
- `regression-encoding-c1.md`
- `regression-encoding-c2.md`
- `poc-plan.md`
- `encoding.md`
- `risk-register.md`
- `../../../adr/0007-upstream-first-and-backend-defaults.md`

Related tooling:

- `../../../tools/poc2-encoding-c3-host/README.md`
- `../../../tools/poc2-encoding-c3-host/FIXTURE-MATRIX.md`
- `../../../tools/poc2-encoding-c3-host/generate-fixtures.ps1`
- `../../../tools/poc2-encoding-c3-host/validate-fixtures.ps1`

---

## 1. Scope

PoC 2-C3はZIP Entry Name MetadataのHistorical Regression Baselineを固定する。

C3では次を対象にする。

- General Purpose Bit Flag bit 11 (EFS / UTF-8)
- raw filename bytes
- Legacy CP932 entry name
- UTF-8 Japanese / Emoji
- NFC / NFD / Combining Character
- ambiguous raw byte sequence
- Info-ZIP Unicode Path Extra Field `0x7075`
- valid / bad CRC / conflicting Unicode Path metadata
- invalid UTF-8 with EFS
- invalid UTF-8 inside `0x7075`
- unknown `0x7075` version
- `.DS_Store`
- `__MACOSX/`
- `._*`

C3 Host GateではLhaForgeを実行しない。Fixtureそのものが意図したRaw ZIP構造であることを先に固定する。

---

## 2. Historical LhaForge Boundary

Current `CArchiver7ZIP` source archaeologyで次を確認している。

```text
ZIP raw metadata
    ↓
7-ZIP32.DLL 9.22.0.2
    ↓
SevenZip* Common Archiver API
    ↓
LhaForge UTF-8 conversion boundary
    ↓
List / Extract filesystem name
```

LhaForgeは`SevenZipSetUnicodeMode(TRUE)`を必須としている。

Archive inspectionでは`SevenZipGetFileName()`が利用できる場合、そのbyte列を`UTILCP_UTF8`としてUnicodeへ変換する。Fallbackの`INDIVIDUALINFO.szFileName`も同様にUTF-8として扱う。

したがってC3 Runtime Stageでは、LhaForge側だけからZIP raw metadataの優先順位を推測せず、固定Fixtureと実際のList / Extract結果を対にして記録する。

---

## 3. Fixture Construction Policy

通常のZIP LibraryにはFilename EncodingやExtra Fieldを自動決定させない。

Host Generatorが次を直接構築する。

```text
Local File Header
Central Directory File Header
End of Central Directory

Raw filename bytes
General Purpose Bit Flags
Extra fields
Stored payload
CRC32
```

C3 v1ではLocal HeaderとCentral DirectoryのFilename / Flags / Extra Fieldを同一に固定する。

Local/Central mismatch、Path Traversal、ADS、Device Path、Symlink / Reparse等はEncoding Baselineから分離し、後続Security Fixtureへ送る。

Fixture生成物は、

```text
.baseline\poc2-encoding\c3-fixtures\
```

へ出力し、RepositoryへBinaryとしてCommitしない。

---

## 4. Independent Validation Policy

Generatorが出力したため正しい、とは扱わない。

`validate-fixtures.ps1`は固定Expected Metadataを持つ別Parserとして、最低限次を検証する。

- Archive SHA-256
- EOCD / Central Directory boundary
- Entry count
- Local / Central filename byte equality
- Local / Central General Purpose Flags equality
- Local / Central Extra Field equality
- Stored payload CRC32
- Payload SHA-256
- `0x7075` field structure
- `0x7075` NameCRC32
- strict UTF-8 validity where relevant
- EFS filename strict UTF-8 validity where relevant

Archive SHA-256はFixture IdentityとしてPrimary Evidenceとする。

将来LhaForgeがArchiveを再生成するRoundtripでは、生成Archive全体のSHA-256をSecondary Evidenceとし、Entry Name semantics / Metadata / PayloadをPrimary Evidenceとする。

---

## 5. Windows PowerShell 5.1 Tooling Correction

初回Host実行ではGeneratorが次のParameter Binding Errorで停止した。

```text
引数が空の配列であるため、パラメーター 'Data' にバインドできません。
```

原因は`macos-metadata` Fixtureの`__MACOSX/` Directory Entryで、Stored payloadとして正当なzero-length `byte[]`をWindows PowerShell 5.1のMandatory Array Parameterへ渡したことだった。

これはLhaForge、ZIP Fixture仕様、Historical BackendのFailureではなくHost Toolingの実装不備である。

修正版ではzero-length byte arrayを意味的に許容するParameterへ`AllowEmptyCollection`を付与し、Generator / Validator双方でFixture処理前にempty byte-array smoke testを実行する。

修正版Host Runでは双方のsmoke testがPASSした。

---

## 6. Frozen Fixture Matrix

| ID | Class | Main metadata | SHA-256 |
| --- | --- | --- | --- |
| `ascii` | `spec-valid` | ASCII / EFS clear | `ce18a398ab39e50f4215c76132602888b59612be150c5c1f46cd2316ef161e2a` |
| `utf8-japanese` | `spec-valid` | UTF-8 Japanese / EFS set | `3157c1131c0bb9fd09802e3716a6892482101f133b089717c1731e4a48bfb12b` |
| `utf8-emoji` | `spec-valid` | UTF-8 Emoji / EFS set | `2917aeef94e2f0b130fc9978fc55968643243c1857c338aec700d641905b5298` |
| `utf8-nfc` | `spec-valid` | UTF-8 NFC / EFS set | `0c5523eda6b603eaa0c19d5a55e78a6255e045a4e96d4915639d8c535c95b51d` |
| `utf8-nfd` | `spec-valid` | UTF-8 NFD / EFS set | `7604c32e7c24626a65df4fcfcc48ceddd8c68cca08009bcc2f632f4e9fbd77cd` |
| `cp932-japanese` | `legacy-observe` | CP932 Japanese / EFS clear | `a3937ae3d1ce93464f754e788187f5c7727e47cb8e542695e9735f8fa4bfabe4` |
| `cp932-ambiguous` | `legacy-observe` | ambiguous bytes / EFS clear | `b70295e558d4e32c8c6afeb24a89c1ade8753b85b69b3b605df44c7bcc113a9b` |
| `cp932-upath-valid` | `metadata-observe` | CP932 + valid 0x7075 | `ce769489ef71130a0ee1a9893b51e768825f235f6b396684f9b87bce2bd9667c` |
| `cp932-upath-bad-crc` | `metadata-observe` | CP932 + bad NameCRC32 0x7075 | `4590a945bc06557628ecea0a1b28d18ea69645a263ff6de22ca7d57f6232f456` |
| `cp932-upath-conflict` | `conflict-observe` | CP932 + conflicting CRC-valid 0x7075 | `f02a51af7bc966d503355479cabd1a5ed32956fd4c4b72039ff7f40b7f7357a9` |
| `utf8-upath-conflict` | `conflict-observe` | EFS UTF-8 + conflicting 0x7075 | `ef9d577380b5eda37a76a1cf4712311a68323f13971b89b111676ed2066fc93b` |
| `invalid-utf8-flag` | `malformed-observe` | EFS set + invalid UTF-8 raw name | `f5a66a68d901a9f0c98f16aecd3df696cebd1f2009aaa04b02fff5394f69dcb8` |
| `upath-invalid-utf8` | `malformed-observe` | CRC-valid 0x7075 + invalid UTF-8 UnicodeName | `8717cbc1e393b46638cd5d6a8728e654b7d0c4d912004ea12229641aa4e21bcb` |
| `upath-unknown-version` | `malformed-observe` | 0x7075 Version 2 | `4f34cccf47f14a653dece50e0b4591f73e46d4b8b417a604048631a5f78aa211` |
| `macos-metadata` | `cross-platform-observe` | payload + .DS_Store + __MACOSX + AppleDouble-style name | `0668be22ca3671dc21bba6e69be000b024727eff156324a109ae18fe59ec0021` |

---

## 7. Host Validation Result

Host execution result:

```text
Generator empty byte-array smoke test: PASS
Generated Fixture count: 15

Validator empty byte-array smoke test: PASS
Independent validation: 15 / 15 PASS
```

All 15 Archive SHA-256 values generated by `generate-fixtures.ps1` matched the fixed values in `validate-fixtures.ps1`.

Observed malformed metadata was also validated as intentionally malformed rather than silently normalized by the Fixture Builder.

Examples:

```text
cp932-upath-bad-crc
  0x7075 version = 1
  NameCRC32 match = false
  UnicodeName strict UTF-8 = true

invalid-utf8-flag
  EFS = set
  raw filename strict UTF-8 = false

upath-invalid-utf8
  0x7075 version = 1
  NameCRC32 match = true
  UnicodeName strict UTF-8 = false

upath-unknown-version
  0x7075 version = 2
```

Host Fixture Gate Classification:

```text
PASS
```

これはApplication Behaviorの`MATCH` Classificationではない。

Original / Modern x86をまだ実行していないため、C3 Runtime Classificationは未確定である。

---

## 8. Runtime Evidence Contract

Formal VM Stageでは各Fixtureについて最低限次を取得する。

```text
fixtureId
archiveSha256

entry[]
  rawNameHex
  generalPurposeFlags
  efs
  extraFieldHex
  unicodePath
    present
    version
    nameCrc32
    nameCrcMatches
    unicodeNameHex
    strictUtf8Valid

Original
  listDisplay
  listCodePoints
  testResult
  extractResult
  extractedFilesystemName
  extractedCodePoints
  payloadSha256
  dialog / warning / error
  processState
  externalState

Modern
  same fields

comparison
  MATCH
  EXPECTED_DIFFERENCE
  REGRESSION
  SECURITY_CHANGE_REQUIRED
  UNKNOWN
```

`.DS_Store` / `__MACOSX` / `._*`はC3では削除せず、Original / Modernがどう表示・展開するかを観測する。

---

## 9. Stop Conditions

Runtime Stageで次が発生した場合は後続Caseを自動継続せず停止する。

- Process crash
- Repeatable access violation
- Wrong-directory extraction
- Fixture以外のFile deletion / overwrite
- External AppData / ProgramData / Registry unexpected mutation
- Path traversal等のSecurity-relevant behavior
- Backend Version / SHA-256 mismatch
- Modern-only regression
- Fixture SHA-256 mismatch

Malformed Fixtureで「Errorになること」自体はStop理由にしない。Expected metadataと異なる外部副作用、Crash、Security relevant behaviorをStop条件とする。

---

## 10. Next Step

次はFormal VM Kit / Runnerを設計する。

Historical RuntimeはPoC 2-C1 / C2と同様に、

```text
Original v1.6.7
Modern x86

7-ZIP32.DLL 9.22.0.2
SHA-256 A82D2B10960F9EBAF5B9D56E2F495C72C22F5DE542740D585AB14CB0B291999C
```

を同一条件へ固定する。

C3 Fixtureは9.22専用にせず、後続PoC 4のOfficial `7z.dll` Backendへ同一Fixtureを再投入する。

現時点ではVM Runtime Resultを記入しない。
