# LhaForge v1.7.0 PoC 2-C Encoding / Path Regression Plan

- Status: In progress / PoC 2-C1 complete / PoC 2-C2 complete
- Baseline: LhaForge v1.6.7 original binary
- Modern comparison: `develop-v1.7.0` x86 Release
- Development branch: `develop-v1.7.0`
- Purpose: x64化・Filename Decode Layer実装前に、Legacy Encoding / Unicode Path / Response File / Cross-platform Archive Metadata / Compound ArchiveのBehaviorをOriginalとModern x86で固定する。

Related documents:

- `regression-baseline.md`
- `regression-archive.md`
- `regression-encoding-c1.md`
- `regression-encoding-c2.md`
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

`7-ZIP32.DLL` 9.22.0.2はPoC 2のHistorical Regression Backendであり、v1.7.x Production標準Backendの候補Versionではない。PoC 2-C3 / 2-C4完了後もHistorical Evidenceとして保持する。

ADR-0007の方針により、7-Zip FamilyのProduction標準候補は後続PoC 4で公式Upstream `7z.dll`をLibraryとして直接利用するAdapterを検証する。C3 Fixtureは9.22専用にせず、Raw ZIP MetadataをDeterministicに固定してOfficial `7z.dll`や将来Backendへ同じFixtureを再投入できる設計とする。


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

Status: **Complete / MATCH (2026-08-13)**

最終RunではASCII / Japanese / Emoji / Supplementary Plane / Combining / NFC / NFDのDirect Path Probe、List / Test、Unicode Compress / Re-extractをOriginal / Modernで比較し、全OperationがPASSした。Final Classificationは`MATCH`で、生成したUnicode roundtrip ZIPのbyte SHA-256も一致した。

Direct Path ProbeはZIP内部EntryをASCII-onlyへ固定し、Archive File NameとOutput Directory Nameだけに対象Unicodeを含めて試験した。`Long Unicode path within current baseline limits`は独立Caseとしては未実施であり、追加のDeep / Long Path境界試験と分離する。

Detailed execution evidence:

- [PoC 2-C1 Direct Unicode Path Regression Result](regression-encoding-c1.md)

PoC 2-C2正常系Baselineは2026-08-13に`MATCH`で完了し、Abnormal Caseも2026-08-23に分離実行して`SECURITY_CHANGE_REQUIRED`で完了した。次はPoC 2-C3へ進む。

---

## 6. PoC 2-C2: Response File

Status: **Complete / Normal MATCH (2026-08-13); Abnormal SECURITY_CHANGE_REQUIRED (2026-08-23)**

Legacy command line parserが持つ`/cp:*`と`/@...` / `/$...`をBaselineとして観測する。

Source確認で次を固定した。

- Response File Code Pageの初期値はSJIS。
- `/cp:utf8` / `/cp:utf-8`はUTF-8、`/cp:utf16` / `/cp:utf-16` / `/cp:unicode`はUTF-16、`/cp:sjis`系AliasはSJISへ切り替える。
- bare `/cp`はSJISへ戻す。
- ParserはCommand Lineを左から順に処理するため、`/cp`は**その後に読むResponse File**へ適用される。
- `/@file`は読込後もResponse Fileを保持する。
- `/$file`は正常読込後にResponse Fileを削除する。読込失敗時は削除処理へ到達しない。
- Response File Readerは変換後の`CR`、`LF`、`NUL`を独立した区切りとして扱い、空行は無視する。
- 各非空行はPathとして扱い、外側のQuoteを外してFile Listへ追加する。
- UTF-8はBOMあり / なしを扱う。
- UTF-16はLE BOM / BE BOMを識別し、BOMなしはNative UTF-16LEとして扱うLegacy behaviorを持つ。
- LegacyのSJIS指定は内部的にWindows ANSI conversionへ依存するため、C2 normal baselineはANSI Code Page `932`をEnvironment Gateとし、異なるVMでは自動設定変更せず停止する。

C2正常系Matrix:

```text
sjis-crlf
utf8-nobom-crlf
utf8-bom-crlf
utf16le-bom-crlf
utf16be-bom-crlf
utf16le-nobom-crlf
utf8-nobom-lf
utf8-nobom-cr
sequence-sjis-then-utf8
sequence-utf8-reset-sjis
dollar-delete-utf8
```

設計上の分離:

- Response File自体のPathはASCII-onlyとし、C1 Direct Unicode Pathを再混入させない。
- Response File内のTarget PathはVM内でCode Pointから生成する。
- CP932 CaseはASCII + CP932 representable Japaneseを使用する。
- UTF系CaseはASCII / Japanese / Emoji / Supplementary Plane / Combining / NFC / NFDを使用する。
- Normal Caseは同じZIP Compression pathへ流し、生成ZIPのEntry Name + Payload SHA-256 FingerprintからParserが選択したInput Setを自動判定する。
- Generated ZIP全体のSHA-256一致はSecondary Observationとし、Input Set / Entry Name / PayloadをPrimary Evidenceとする。
- `/@` CaseではResponse File working copyがbyte-identicalで残ること、`/$` Caseでは削除されることを確認する。
- C1 Evidenceとは別の`fixture-response` / `response-results` / `evidence-response`を使用する。

各Caseで次を記録する。

- Response File raw SHA-256
- BOM
- Newline
- Command line argument order
- Expected Target file list
- Generated ZIP logical Entry Name
- Payload SHA-256
- Operation result
- Response File post-state
- External AppData / ProgramData state

Invalid `/cp`、Invalid UTF-8、Invalid / odd-length UTF-16等は正常系と分離し、Normal MatrixのOriginal / Modern比較完了後にAbnormal Caseとして扱った。

正常系最終RunではOriginal / Modernとも11 / 11 CaseがPASSし、Final Classificationは`MATCH`となった。`/@` CaseはResponse Fileをbyte-identicalのまま保持し、`/$` Caseは正常読込後に削除された。External AppData / ProgramData stateに差異はなく、Generated ZIP byte SHA-256も11 / 11 pair一致した。

C2 Abnormal Matrix:

```text
invalid-cp-value
invalid-cp-syntax
invalid-utf8-at
invalid-utf8-dollar
utf16le-lone-surrogate-at
utf16le-odd-at
utf16be-odd-at
```

Abnormalでは最初の5 CaseをSource-derived expectation付き`asserted`、odd-length UTF-16LE / BEを`observe-only`として実行した。Original / Modernともasserted 5 / 5が期待値へ一致し、observe-only 2 CaseもBehavior signatureが一致した。全14 RunでExit Codeは0、Crash / Timeout / Archive生成はなく、External AppData / ProgramDataおよび追跡対象`%TEMP%\zip*.tmp`にDriftはなかった。Invalid UTF-8はReplacementを含む存在しないPathとして後段Validationへ到達し、`/@`はResponse Fileを保持、`/$`は後段Failureより前にResponse Fileを削除するLegacy behaviorをOriginal / Modern双方で確認した。

odd-length UTF-16LE / BEについてはBehavioral Parity自体は確認できたが、奇数byte長を検証せずLegacy `WCHAR*`処理へ渡す挙動を互換要件として保存しない。Abnormal Final Classificationは`SECURITY_CHANGE_REQUIRED`とし、Production modernization時にodd-length UTF-16を明示的にRejectするSource-level hardening requirementとして引き継ぐ。

Detailed execution evidence:

- [PoC 2-C2 Response File Encoding / Newline Regression Result](regression-encoding-c2.md)

C2全体はCompleteとする。正常系EvidenceはTested HEAD `ef915cad9913582f42bdd737d33104c4e77dd1b8`、Abnormal EvidenceはTested HEAD `d1e28e1c75399ea8ce6f187d0329e50a9e519c0d`のHistorical BaselineとしてそれぞれFreezeし、次はPoC 2-C3へ進む。

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
2. C2 Response Fileの主要Encoding / Newline / Abnormal Caseを比較済みで、Legacy behaviorを維持しないSafety DifferenceをDocument化済み。
3. C3 ZIP Filename MetadataのUTF-8 / CP932 / ambiguous Caseを比較済み。
4. NFC / NFD等Cross-platform oriented Fixtureを比較済み。
5. C4 Compound Archiveの固定Backend / Fixtureで主要Operationを比較済み、または明確なBlockerをDocument化済み。
6. Modern only regressionが未解決で残っていない。
7. Known Difference / Legacy LimitationをDocument化済み。
8. macOS実機未検証項目を明示済み。
9. Payload bytesが不要に変換されないことを確認済み。
10. PoC 3開始前に必要なEncoding / Path Baselineが固定されている。
