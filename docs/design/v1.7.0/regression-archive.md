# PoC 2-B Archive Basic Operation Regression

- Status: **Complete / MATCH**
- Scope: Original LhaForge v1.6.7 vs Modern x86
- Primary format: ZIP
- Backend: same fixed `7-ZIP32.DLL` bytes in both targets
- VM baseline: `PoC2-A Config Regression Passed`
- Fixed backend: `7-ZIP32.DLL` 9.22.0.2 / x86
- Fixed backend SHA-256: `a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c`
- Reference ZIP SHA-256: `bfa93a8eef9bf5c9c83ae7ec840b1be7d9436d6e912fd3a801ccf21e22115ad5`

Related:

- [Regression Baseline](regression-baseline.md)
- [PoC Plan](poc-plan.md)
- [PoC 2-A UI Regression](regression-ui.md)
- [PoC 2-A Config Save / Reload Regression](regression-config.md)
- [Archive Backend Design](backend.md)

---

## 1. Purpose

PoC 2-Bでは、Actual x64化へ進む前に、Modern ToolchainでBuildしたx86 `LhaForge.exe`がv1.6.7の基本Archive操作を維持していることを確認する。

対象:

```text
List
Test
Extract
Compress
Re-extract
```

PoC 2-BはZstandard / ZSTEの新実装試験ではない。

Zstd / ZSTEはArchitecture checkpointとして先に設計を記録したが、ここではv1.6.7が既に利用しているZIP + `7-ZIP32.DLL`経路をRegression Baselineとして固定する。

---

## 2. Source findings

### 2.1 ZIP backend identity

`CArchiver7ZIP`は次を固定する。

```text
DLL name: 7-ZIP32.DLL
Required version: 920
Required subversion: 2
Function prefix: SevenZip
```

Load後に`SevenZipSetUnicodeMode(TRUE)`を要求し、Unicode Modeへ切り替えられないDLLはInvalid扱いとなる。

したがってPoC 2-Bでは、単に同名DLLを使うのではなく、Original / Modernに**同一SHA-256のx86 DLL**を配置する。

### 2.2 Runtime DLL search behavior

v1.6.7の`CArchiverDLL::LoadDLL()`は、DLL Load前に`UtilGetModuleDirectoryPath()`へCurrent Directoryを一時変更してから、

```text
LoadLibrary("7-ZIP32.DLL")
```

を実行する。

そのためBaselineを忠実にするには、

```text
original\LhaForge.exe
original\7-ZIP32.DLL

modern\LhaForge.exe
modern\7-ZIP32.DLL
```

とEXE直下へ同じDLLを置く。

将来設計の`dll\x86\` LayoutをPoC 2-Bへ先取りしない。

### 2.3 ZIP compression path

ZIP圧縮は7-Zip互換Commandを生成し、`ArchiveHandler`へ渡す。

基本:

```text
a
-tzip
-r0
```

v1.6.7 Default ZIP設定では`CompressType=0`がDeflate、`CompressLevel=0`がLevel 5に対応する。

ただしRegressionではConfig Defaultへの依存を減らすため、CLIで明示的に、

```text
/method:Deflate
/level:5
```

を指定する。

圧縮InputはUTF-8 Response Fileへ書き、`-scsUTF-8`を指定する。作業DirectoryはLhaForgeのTemp Pathを`-w`で7-Zip側へ渡す。

### 2.4 Extraction path

ZIP展開は概ね、

```text
x
-scsUTF-8
-w<temp>
<archive>
```

を`ArchiveHandler`へ渡す。

LhaForge側のArchive安全判定でUnsafeと判断されたArchiveは`CArchiver7ZIP::Extract()`へ到達しても拒否される。

PoC 2-BのReference ZIPは通常Pathのみを持つ安全なFixtureとする。

### 2.5 Test path

`CArchiver7ZIP::TestArchive()`は7-Zipの、

```text
t "<archive>"
```

を使用する。

`/t` CLIは`DoTest()`へ入り、最終結果をDialog表示する。

v1.6.7ではこの結果をMachine-readableなProcess Exit CodeとしてRegression Harnessへ返す設計ではないため、PoC 2-BではTest Dialogを目視確認し、その結果をKitへ記録する。

### 2.6 List path

`/l` CLIは`DoList()`へ入り、`CFileListFrame`でArchiveをOpenする。

List WindowはMessage Loopを持つため、Windowを閉じるまでProcessは終了しない。

PoC 2-BではReference ZIPのLogical Treeを目視確認する。Directory Entryの表示形式やRow数だけをPrimary判定にはしない。

### 2.7 CLI controls used by the kit

Source上、次を利用できる。

```text
/l
/t
/e
/c:zip
/o:<directory>
/f:<filename>
/method:<method>
/level:<level>
/mkdir:no
/popdir:yes
/cfg:<path>
```

これを利用し、Original / Modernの操作条件を可能な限りCommand Lineで固定する。

---

## 3. Fixed fixture

PoC 2-BはASCII Pathだけを使用する。

```text
fixture\input\
├─ root.txt
├─ empty.txt
├─ nested\
│  ├─ child.txt
│  └─ binary.bin
└─ another\
   └─ data.txt
```

Japanese Path、CP932 / UTF-8 Filename、Deep Path等はPoC 2-Cで扱う。

Reference ZIPはHost Kit生成時に一度作成し、Original / Modernの両方が同じByte列を読む。

---

## 4. Compression regression rule

OriginalとModernが生成したZIPのBinary SHA-256一致をPrimary条件にしない。

理由:

- Timestamp
- Entry Metadata
- Entry order
- Encoder implementation detail

等でBinary差が生じても、Archive semanticsが同一の場合がある。

Primary:

```text
Fixture
  -> Compress
  -> generated ZIP can be opened
  -> Re-extract
  -> Path / Size / SHA-256 equality
```

生成ZIPのSHA-256自体はEvidenceとして保存する。

---

## 5. Automated criteria

`compare-archive-results.ps1`は少なくとも次を比較する。

- Original / Modernで同一`7-ZIP32.DLL` SHA-256
- Reference ZIP Extract結果 vs Fixture
- Original vs Modern Extract結果
- Original Compress -> Re-extract vs Fixture
- Modern Compress -> Re-extract vs Fixture
- Original vs Modern Re-extract結果
- Generated ZIPを.NET `ZipArchive`でOpen可能
- Generated ZIPのLogical File Name / Uncompressed Size
- AppData / ProgramData `LhaForge`内容の意図しない変更
- `zip*.tmp`の新規残留をEvidence化

File内容はSHA-256で比較する。

---

## 6. Manual criteria

List / Testはv1.6.7 UIが結果を表示するため、次を目視確認する。

### List

Reference ZIPのLogical Treeが正しく表示され、Archive Open Errorがない。

### Test

Archive Test Resultが成功し、Archive Errorがない。

Kitの`run-archive-operation.ps1`はList / Test終了後に`y/n`で結果を記録する。

---

## 7. Host preparation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-archive-regression.ps1 `
  -OriginalExe "C:\Program Files (x86)\LhaForge\LhaForge.exe" `
  -SevenZipDll "C:\Path\To\7-ZIP32.DLL"
```

再生成:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-archive-regression.ps1 `
  -OriginalExe "C:\Program Files (x86)\LhaForge\LhaForge.exe" `
  -SevenZipDll "C:\Path\To\7-ZIP32.DLL" `
  -Force
```

生成物:

```text
.baseline\poc2-archive\vm-kit\
.baseline\poc2-archive\poc2-archive-vm-kit.zip
```

LFCaldixによる自動DownloadはRegression中に使用しない。

---

## 8. VM procedure

VM Kit内の`CHECKLIST.md`を正とする。

開始Snapshot:

```text
PoC2-A Config Regression Passed
```

VM Local Fixed DiskへKitを展開して実行する。

---

## 9. Pass classification

最終期待:

```text
[POC2-ARCHIVE] Classification: MATCH
```

Manual List/Testがまだ記録されていないがAutomated結果が一致している場合:

```text
AUTOMATED_MATCH_MANUAL_PENDING
```

差異がある場合:

```text
MISMATCH
```

---


## 10. Execution result

2026-08-08にClean VM baselineからOriginal / Modernを同一条件で実行した。

最終結果:

```text
Original
  List        PASS
  Test        PASS
  Extract     PASS
  Compress    PASS
  Re-extract PASS
  Capture     PASS

Modern
  List        PASS
  Test        PASS
  Extract     PASS
  Compress    PASS
  Re-extract PASS
  Capture     PASS

[POC2-ARCHIVE] Classification: MATCH
```

`compare-archive-results.ps1`で次をすべて確認した。

```text
[OK] Original and Modern use the same 7-ZIP32.DLL bytes.
[OK] Staged DLL matches the selected host DLL.
[OK] Original extraction matches the fixture by path, size, and SHA-256.
[OK] Modern extraction matches the fixture by path, size, and SHA-256.
[OK] Original and Modern extraction results match.
[OK] Original compress -> re-extract matches the fixture.
[OK] Modern compress -> re-extract matches the fixture.
[OK] Original and Modern roundtrip results match.
[OK] Original compressed ZIP can be opened by .NET ZipArchive.
[OK] Modern compressed ZIP can be opened by .NET ZipArchive.
[OK] Original compressed ZIP has the expected logical files and sizes.
[OK] Modern compressed ZIP has the expected logical files and sizes.
[OK] Original and Modern compressed ZIP semantic file lists match.
[OK] Original did not change AppData LhaForge file content.
[OK] Original did not change ProgramData LhaForge file content.
[OK] Modern did not change AppData LhaForge file content.
[OK] Modern did not change ProgramData LhaForge file content.
[OK] Original left no new zip*.tmp residue.
[OK] Modern left no new zip*.tmp residue.
[OK] original List UI showed the expected archive contents.
[OK] original archive Test UI reported success.
[OK] modern List UI showed the expected archive contents.
[OK] modern archive Test UI reported success.
```

最終RunではOriginal / Modernが生成した`roundtrip.zip`のSHA-256も一致した。

```text
cadf291a9971939b32b3f236ab5907f518880c79b7dc9f5d3af573a5155f708f
```

ただしBinary ZIP hash一致はPrimary Pass条件へ昇格しない。Compression regression ruleは引き続きSemantic EntryとRe-extract結果をPrimaryとする。

---

## 11. Regression discovered during PoC 2-B

最初のModern Release|Win32 List試験では、Originalが正常だった同一Reference ZIP / 同一`7-ZIP32.DLL`条件でModernだけCrashした。

```text
Original List
  Process exit code: 0
  Manual result: PASS

Modern List before fix
  Process exit code: -1073741819
  NTSTATUS: 0xC0000005
  Faulting module: LhaForge.exe
  Fault offset: 0x0003FEC9
  Manual result: FAIL
```

同一Fault offsetで複数回再現したため、偶発CrashではなくDeterministic regressionとして調査した。

WER LocalDumpsで取得したFull dump:

```text
LhaForge.exe.7200.dmp
SHA-256:
4425067e409b68bd14b78c3006e0abe65c2ba1fc45191364bea3801b9098cfc7
```

Crash時のRelease executable:

```text
LhaForge.exe
SHA-256:
d5b15520d7fdf46eb410135393a7f9505197d6a6c02bf4596b535e527e792b3b
```

PDB / Dump解析では、List WindowのSort pathにある`FileListModel.cpp`のComparator `COMP::operator()`でNULL `this`をDereferenceしていた。

Source archaeologyにより、次の2 Translation UnitがGlobal namespaceへ異なる定義の`struct COMP`を持つことを確認した。

```text
FileListWindow/FileListModel.cpp
  struct COMP
    FILEINFO_TYPE Type
    bool bReversed

Dialogs/LogListDialog.cpp
  struct COMP
    int nCol
```

これはOne Definition Rule違反である。Legacy CompilerではTranslation Unit単位で偶然問題化しなかったが、Modern Release buildのWhole Program Optimization / LTCGでSTL Comparatorの型Identityが衝突し、List Sort pathでRuntime failureとして顕在化したと判断した。

### Fix

Behavior logicを変えず、Comparator typeをTranslation Unitごとに固有化した。

```text
FileListModel.cpp
  COMP
    ->
  FILELIST_ENTRY_COMP

LogListDialog.cpp
  COMP
    ->
  LOG_LIST_COMP
```

Legacy Source encoding / line endingは維持した。

```text
Encoding: CP932
Line ending: CRLF
```

修正後、同一Reference ZIP / 同一`7-ZIP32.DLL`でModern Listを再試験した。

```text
Process exit code: 0
Expected logical file tree: PASS
Manual result: y
```

その後Original / Modern双方のPoC 2-B全操作をFresh initializationから再実行し、最終Classification `MATCH`を得た。

この修正は一時的なOptimizer回避ではなく、Legacy Sourceに元から存在したODR違反そのものを除去するCompatibility fixとして保持する。

---

## 12. Baseline interpretation

PoC 2-Bで使用した`7-ZIP32.DLL` 9.22.0.2は、v1.6.7互換性を測定するためのHistorical Regression Backendとして固定する。

これはv1.7.xが最終的にこのDLLだけを使用することを意味しない。

今後のBackend Modernizationでは、

```text
Historical Regression Backend
  fixed 7-ZIP32.DLL 9.22.0.2

Current External Backend
  supported current DLL versions

Legacy x86 DLL
  x64 Main Application -> LegacyHost

Built-in Backend
  fallback when external backend is unavailable / ineligible
```

を分離して扱う。

Regression Baselineを更新DLLで置き換えず、旧Behavior互換の物差しとして保持する。

---

## 13. Exit criteria

PoC 2-B完了条件:

1. Same fixed x86 `7-ZIP32.DLL` used by both targets
2. List PASS
3. Test PASS
4. Extract MATCH
5. Compress -> Re-extract MATCH
6. Generated ZIP readable
7. No crash
8. No unexplained external state change
9. Result evidence preserved

Pass後はPoC 2-CとしてJapanese Filename / CP932 / UTF-8 / Response File / Compound Archive等へ進む。
