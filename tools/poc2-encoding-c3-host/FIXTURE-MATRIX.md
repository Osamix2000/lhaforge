# PoC 2-C3 Fixture Matrix v1

このMatrixはHost-side Raw ZIP Fixtureのv1候補です。Application BehaviorのExpected Resultを早期固定するものではありません。

Primary目的は、

```text
Original v1.6.7
vs
Modern x86
```

のBehavioral Parityを同一Raw Metadataで比較することです。

後続PoC 4では同一FixtureをOfficial `7z.dll` Backendへ再投入します。

| ID | Class | Raw name / Metadata | C3 observation |
| --- | --- | --- | --- |
| `ascii` | spec-valid | ASCII, EFS clear | 基本Control |
| `utf8-japanese` | spec-valid | UTF-8 Japanese, EFS set | bit 11 UTF-8 |
| `utf8-emoji` | spec-valid | UTF-8 supplementary-plane Emoji, EFS set | non-BMP |
| `utf8-nfc` | spec-valid | `café.txt` NFC, EFS set | normalization保持 |
| `utf8-nfd` | spec-valid | `cafe + U+0301`, EFS set | combining / NFD保持 |
| `cp932-japanese` | legacy-observe | Japanese CP932, EFS clear | Legacy Windows decode |
| `cp932-ambiguous` | legacy-observe | `C2 A9 2E 74 78 74`, EFS clear | UTF-8では`©.txt`、CP932では別文字列 |
| `cp932-upath-valid` | metadata-observe | CP932 raw + valid `0x7075` | Unicode Path support / precedence |
| `cp932-upath-bad-crc` | metadata-observe | CP932 raw + bad NameCRC32 `0x7075` | invalid Unicode Path ignore behavior |
| `cp932-upath-conflict` | conflict-observe | CP932 raw + CRC-valid conflicting UnicodeName | metadata precedence |
| `utf8-upath-conflict` | conflict-observe | EFS UTF-8 + conflicting `0x7075` | intentionally non-conformant precedence |
| `invalid-utf8-flag` | malformed-observe | EFS set + invalid UTF-8 raw name | reject / replacement / error / crash observation |
| `upath-invalid-utf8` | malformed-observe | CRC-valid `0x7075` + invalid UTF-8 UnicodeName | malformed extra field handling |
| `upath-unknown-version` | malformed-observe | `0x7075` Version 2 | unknown version handling |
| `macos-metadata` | cross-platform-observe | `payload.txt`, `.DS_Store`, `__MACOSX/`, `__MACOSX/._payload.txt` | C3ではfilterせず表示・展開を観測 |


## Host validation freeze

The 15-case matrix was generated and independently validated on 2026-08-30 with Windows PowerShell 5.1 Desktop. All cases passed structural, raw-name, flag, extra-field, CRC, payload and fixed archive-hash validation.

| ID | SHA-256 |
| --- | --- |
| `ascii` | `ce18a398ab39e50f4215c76132602888b59612be150c5c1f46cd2316ef161e2a` |
| `utf8-japanese` | `3157c1131c0bb9fd09802e3716a6892482101f133b089717c1731e4a48bfb12b` |
| `utf8-emoji` | `2917aeef94e2f0b130fc9978fc55968643243c1857c338aec700d641905b5298` |
| `utf8-nfc` | `0c5523eda6b603eaa0c19d5a55e78a6255e045a4e96d4915639d8c535c95b51d` |
| `utf8-nfd` | `7604c32e7c24626a65df4fcfcc48ceddd8c68cca08009bcc2f632f4e9fbd77cd` |
| `cp932-japanese` | `a3937ae3d1ce93464f754e788187f5c7727e47cb8e542695e9735f8fa4bfabe4` |
| `cp932-ambiguous` | `b70295e558d4e32c8c6afeb24a89c1ade8753b85b69b3b605df44c7bcc113a9b` |
| `cp932-upath-valid` | `ce769489ef71130a0ee1a9893b51e768825f235f6b396684f9b87bce2bd9667c` |
| `cp932-upath-bad-crc` | `4590a945bc06557628ecea0a1b28d18ea69645a263ff6de22ca7d57f6232f456` |
| `cp932-upath-conflict` | `f02a51af7bc966d503355479cabd1a5ed32956fd4c4b72039ff7f40b7f7357a9` |
| `utf8-upath-conflict` | `ef9d577380b5eda37a76a1cf4712311a68323f13971b89b111676ed2066fc93b` |
| `invalid-utf8-flag` | `f5a66a68d901a9f0c98f16aecd3df696cebd1f2009aaa04b02fff5394f69dcb8` |
| `upath-invalid-utf8` | `8717cbc1e393b46638cd5d6a8728e654b7d0c4d912004ea12229641aa4e21bcb` |
| `upath-unknown-version` | `4f34cccf47f14a653dece50e0b4591f73e46d4b8b417a604048631a5f78aa211` |
| `macos-metadata` | `0668be22ca3671dc21bba6e69be000b024727eff156324a109ae18fe59ec0021` |

## Deliberately deferred

次はC3 v1 Fixtureへ入れません。

- Local Header filenameとCentral Directory filenameの不一致
- Local / CentralのEFS flag不一致
- Header lengthがArchive境界を越える構造破損
- Path Traversal
- Absolute Path
- ADS
- Device Path
- Symlink / Reparse Point

これらはFilename Encoding Baselineとは別のSecurity / malformed archive軸を混ぜるため、PoC 8またはC3後の独立Security Fixtureとして扱います。

## Evidence fields planned for VM stage

各Caseで最低限次を記録します。

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

Modern
  same fields

comparison
  MATCH
  EXPECTED_DIFFERENCE
  REGRESSION
  SECURITY_CHANGE_REQUIRED
  UNKNOWN
```

Generated ZIP全体のSHA-256はFixture IdentityとしてPrimaryです。

一方、LhaForgeが将来Archiveを再生成するRoundtrip Testを追加する場合、生成Archive全体のByte SHA-256はSecondary Evidenceとし、Entry Name semantics / Metadata / PayloadをPrimaryにします。
