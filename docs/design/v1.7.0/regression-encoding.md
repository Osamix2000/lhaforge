# LhaForge v1.7.0 PoC 2-C Encoding / Path Regression Plan

- Status: Planned / pre-execution
- Baseline: LhaForge v1.6.7 original binary
- Modern comparison: `develop-v1.7.0` x86 Release
- Development branch: `develop-v1.7.0`
- Purpose: x64化・Filename Decode Layer実装前に、Legacy Encoding / Unicode Path / Response File / Cross-platform Archive Metadata / Compound ArchiveのBehaviorをOriginalとModern x86で固定する。

Related documents:

- `regression-baseline.md`
- `regression-archive.md`
- `encoding.md`
- `archive-operations.md`
- `archive-result-ui.md`
- `poc-plan.md`
- `risk-register.md`

---

## 1. Principle

PoC 2-Cは新しいFilename Auto Detection、Manual Override、Extraction Exclusion、Modern Result UIを実装するPoCではない。

まずOriginal v1.6.7とModern x86の現在Behaviorを同一Fixture / 同一Backendで観測し、次を区別する。

```text
MATCH
EXPECTED_DIFFERENCE
REGRESSION
SECURITY_CHANGE_REQUIRED
UNKNOWN
```

Legacy Behaviorを測定せずにModernization Featureを混在させない。

---

## 2. Goals

PoC 2-Cでは少なくとも次を確認する。

1. Direct Unicode PathをOriginal / Modernが同じように扱うか。
2. Japanese / CP932 representable Nameを壊さないか。
3. CP932で表現不能なUnicode NameのBehaviorを観測する。
4. ZIP Entry NameのUTF-8 / Legacy CP932 Metadataを観測する。
5. NFC / NFD / Combining Character等のUnicode表現差を観測する。
6. Response File Encoding / Newlineを観測する。
7. File List / Test / Extract / Compress / Re-extractのうち意味のあるOperationを比較する。
8. Compound ArchiveのLogical Name / basic operationを比較する。
9. Cross-platform Archive MetadataのBaseline Fixtureを作る。
10. macOS由来Metadata (`.DS_Store`, `__MACOSX`, `._*`) を観測Fixtureとして扱う。
11. 文字化け、Decode Failure、Archive Corruptionを同一原因として扱わない。
12. PoC中にCrash / Data Loss / unexpected external state changeが出た場合はそこで停止して原因調査する。

---

## 3. Non-Goals

PoC 2-Cでは次をまだProduction実装しない。

- New Filename Decode Core
- Raw Entry Name ModelのProduction実装
- User-facing Manual Encoding Override
- 解凍前Preview UI
- File List WindowのEncoding切替UI
- Extraction Exclusion Rule Engine
- `.DS_Store`等の自動除外
- Archive Result / Error UI Modernization
- x64 Main Application
- LegacyHost
- Built-in Backend
- Zstandard / ZSTE implementation

これらの必要性とTest CaseをBaseline Evidenceから確定する。

---

## 4. Fixed Backend Policy

PoC 2-C1から2-C3のZIP系検証では、PoC 2-Bと同じHistorical Regression Backendを使用する。

```text
7-ZIP32.DLL
Version: 9.22.0.2
SHA-256:
A82D2B10960F9EBAF5B9D56E2F495C72C22F5DE542740D585AB14CB0B291999C
Architecture: x86
```

これはv1.7.xの最終Backend Versionを固定するものではない。

PoC 2-C4 Compound Archiveで別DLLが必要になる場合は、その段階でVersion / PE Architecture / SHA-256を固定し、ZIP系結果と混在させない。

---

## 5. PoC 2-C1: Direct Unicode Path

対象Fixture候補:

```text
ASCII
Japanese
CP932 representable Japanese
Unicode not representable in CP932
Emoji
Supplementary Plane Character
Combining Character
NFC name
NFD name
Nested Unicode directory
Long Unicode path within current baseline limits
```

確認:

- LhaForge command lineへ直接Pathを渡す
- List
- Test
- Extract
- Compress
- Compress -> Re-extract
- Entry logical name
- Extracted filesystem name
- Payload SHA-256
- External state
- Temp residue

Original / Modernで同一Fixtureを使用する。

---

## 6. PoC 2-C2: Response File

Legacy command line parserが持つ`/cp:*`と`/@...` / `/$...`をBaselineとして観測する。

Encoding / Newline Matrix候補:

```text
CP932          + CRLF
UTF-8 no BOM   + LF
UTF-8 BOM      + CRLF
UTF-16LE BOM   + CR
UTF-16BE BOM   + CRLF
```

各Caseで次を記録する。

- Response File raw SHA-256
- BOM
- Newline
- Command line argument order
- Parser result
- Target file list
- Operation result
- Output path / name
- Error message when rejected

`/cp`指定とResponse File指定の順序依存がある場合はBehaviorとして記録する。

Invalid UTF-8 / Invalid UTF-16は正常系と分離し、Abnormal Caseとして扱う。

---

## 7. PoC 2-C3: Archive Entry Name Metadata

ZIP Fixture候補:

```text
UTF-8 flag / Unicode metadata
Legacy CP932 entry name
ASCII-only name
Ambiguous byte sequence
Invalid UTF-8 sequence
NFC entry name
NFD entry name
Combining character
Emoji / supplementary character
```

観測:

- Raw archive fixture SHA-256
- Entry byte metadata (Fixture builder側で既知の場合)
- Original List表示
- Modern List表示
- Extracted filesystem name
- Unicode code point sequence
- Test result
- Extract result
- Roundtrip result where meaningful
- Error / warning text

Binary ZIP全体のSHA-256一致はSecondary Evidenceとし、Filename semantics / payload / roundtripをPrimary Evidenceとする。

---

## 8. Cross-platform / macOS-oriented Fixtures

手元にmacOS実行環境がなくてもDeterministic Fixtureを作成できる項目はPoCへ含める。

```text
NFC vs NFD
Combining Character
.DS_Store
__MACOSX/
._*
UTF-8 filename metadata
```

`.DS_Store` / `__MACOSX` / `._*`はこのPoCでは削除しない。

Original / Modernがどう表示・展開するかをBaselineとして記録する。

実際のFinder / macOS標準Tool等が生成したArchiveは、入手できるまで`real macOS generated fixture: not yet verified`と明記する。

macOS実機をPoC 2-CのCompletion Blockerにはしない。

---

## 9. PoC 2-C4: Compound Archive

候補:

```text
.tar.gz
.tgz
.tar.bz2
.tbz / .tbz2
.tar.xz
.txz
.tar.lzma
```

確認:

- Format detection
- List / Test / Extract
- Create where baseline backend supports
- Logical archive base name
- Nested filename encoding
- Compound suffix behavior
- Original / Modern equivalence

TAR系DLL等の新しいBackend dependencyが必要になる場合は、開始前に固定Backend EvidenceをDocumentへ追加する。

---

## 10. Filename Evidence

単なるExplorer Screenshotだけでなく、可能なCaseではUnicode code pointを記録する。

例:

```text
Display: ...
Code points: U+.... U+....
Normalization observation: NFC / NFD / unchanged
```

v1.7.xはActual File Nameを勝手にNormalizationしない方針のため、見た目が同じでもCode Point列が異なるCaseを区別する。

---

## 11. File Payload Policy

Archiveから展開したUser File Contentsについて、Encoding / BOM / NewlineをLhaForgeが変換しないことを確認する。

比較はFile内容のSHA-256を基本とする。

```text
Archive payload bytes
        ->
Extract
        ->
same bytes
```

Filename Metadata DecodeとUser File Content Encodingを混同しない。

---

## 12. Error and Ambiguity Capture

文字化け、Decode Failure、Unsupported Encoding、Archive Corruptionを別Caseとして記録する。

保存Evidence候補:

- Exit code
- LhaForge message
- Backend raw log
- WER / Exception when crash
- File / folder name display
- Output filesystem state
- Temp residue
- AppData / ProgramData / Registry change
- Screenshot / manual confirmation where UI evidence is required

不明なCaseを無理に原因分類せず`UNKNOWN`とする。

---

## 13. Stop Conditions

次が発生した場合は後続Caseを継続せず原因調査を優先する。

- Process crash
- Repeatable access violation
- Fixture以外のFile deletion / overwrite
- External AppData / ProgramData / Registry unexpected mutation
- Wrong-directory extraction
- Path traversal / security-relevant behavior
- Modern only regression
- Backend bytes / version mismatch

PoC 2-BでCrashを発見した時と同じく、Failを隠して一括実行しない。

---

## 14. Future Design Requirements Confirmed Before PoC

PoC 2-C実装後のModernizationでは、次の方向を正式要件として扱う。

### Shared Filename Decode Policy

```text
Raw / backend metadata
       ->
Filename Decode Policy
       ->
Unicode Entry Name
       +--> File List
       +--> Extraction Preview
       `--> Extraction
```

閲覧 / Preview / 解凍で別Decode実装を持たない。

### Raw Entry Name

Backend / FormatがRaw Entry Name Bytesを公開できる場合は保持し、Auto DecodeとManual Overrideの再Decode元にする。

### Manual Override

解凍UI:

```text
解凍時のファイル・フォルダー名の文字コード
[ 自動判定（推奨） ]

解凍後のファイル・フォルダー名が文字化けする場合に変更してください。
```

File List Window:

```text
ファイル・フォルダー名の文字コード
[ 自動判定（推奨） ]
```

Encoding確定FormatでもManual Overrideを許可するAdvanced Optionを設計する。

### Extraction Preview

解凍DialogにPreview Buttonを提供する方向とし、Preview Window内でもFilename Encodingを切り替えられるようにする。

### Extraction Exclusion

`.DS_Store`、`__MACOSX`、`._*`等を含むExtraction FilterをOperation Planner側へ追加する。

原則として「一度展開してから削除」ではなく、Final Extraction Setから外してFilesystemへ書き出さない。

---

## 15. Planned Test Kit

PoC 2-B Kitと同様に、Host準備とVM実行を分離する。

予定構成:

```text
tools/
├─ prepare-poc2-encoding-regression.ps1
└─ poc2-encoding-vm/
   ├─ common.ps1
   ├─ initialize-encoding-regression.ps1
   ├─ run-encoding-case.ps1
   ├─ capture-encoding-result.ps1
   ├─ compare-encoding-results.ps1
   └─ CHECKLIST.md
```

Windows PowerShell 5.1で実行するRepository Scriptは、可能な限りASCII-onlyとする。

Unicode Fixture名はScript Sourceへ直接日本語を埋め込まず、Code Point / Byte列からDeterministicに生成する方向とする。

---

## 16. Completion Criteria

PoC 2-CをCompleteとする最低条件:

1. C1 Direct Unicode Pathの主要CaseをOriginal / Modernで比較済み。
2. C2 Response Fileの主要Encoding / Newline Caseを比較済み。
3. C3 ZIP Filename MetadataのUTF-8 / CP932 / ambiguous Caseを比較済み。
4. NFC / NFD等Cross-platform oriented Fixtureを比較済み。
5. C4 Compound Archiveの固定Backend / Fixtureで主要Operationを比較済み、または明確なBlockerをDocument化済み。
6. Modern only regressionが未解決で残っていない。
7. Known Difference / Legacy LimitationをDocument化済み。
8. macOS実機未検証項目を明示済み。
9. Payload bytesが不要に変換されないことを確認済み。
10. PoC 3開始前に必要なEncoding / Path Baselineが固定されている。
