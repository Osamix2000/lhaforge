# LhaForge v1.7.0 Archive Result / Error UI Design

- Status: Draft / accepted direction
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Development branch: `develop-v1.7.0`
- Scope: Archive List / Test / Extract / Create等のOperation Result、Error表示、User-facing Diagnostic Export

Related documents:

- `architecture.md`
- `archive-operations.md`
- `logging.md`
- `encoding.md`
- `security.md`
- `performance.md`
- `poc-plan.md`
- `risk-register.md`

---

## 1. Purpose

v1.6.7のArchive Result / Error表示は、Backend由来LogやEntry単位の結果を確認できる一方、大量Entryや長いMessageで扱いづらいCaseがある。

v1.7.xでは、既存の診断情報を失わずに、通常Userには結果を理解しやすく、DeveloperへLogを渡した場合には原因調査へ直結できるResult / Error UIへModernizeする。

本設計はRaw Backend Logを削除・置換するものではない。

```text
Structured Operation Result
        |
        +--> Summary First UI
        |
        +--> Entry Result List
        |
        +--> Detailed Diagnostic
        |
        `--> Raw Backend Log
```

---

## 2. Core Principles

1. 初期表示はSummary Firstとする。
2. Summaryだけでも成功 / 部分失敗 / 失敗 / 不明を判断できる。
3. LhaForge側のStable Error CodeとBackendのRaw Errorを分離して保持する。
4. Backendが原因を特定できない場合に、LhaForgeが推測で原因を断定しない。
5. `UnknownFailure` / `UnknownBackendError`等のUnknown状態を正式に扱う。
6. Raw Backend Logを失わない。
7. 大量Entry数によってWindowそのものを縦方向へ無制限に拡大しない。
8. User Resize、Scroll、Maximizeを許可する。
9. Copy / SaveしたDiagnosticはSupport / Debugに意味のある情報を含む。
10. Password、Token、User File内容等のSecretはDiagnosticへ記録しない。
11. Encoding ErrorとArchive Corruptionを混同しない。
12. Test / Extract等で共通Result Modelを利用し、UI文言だけOperationに合わせる。

---

## 3. Operation Result Model

Operation全体の結果候補:

```text
Success
PartialSuccess
Failed
UnknownFailure
Canceled
```

Entry単位では、少なくとも次のような結果とReasonを分離して保持する。

```text
EntryResult
├─ Status
│  ├─ OK
│  ├─ Failed
│  ├─ Skipped
│  └─ Unknown
│
└─ Reason
   ├─ CRCError
   ├─ DataError
   ├─ TruncatedArchive
   ├─ InvalidHeader
   ├─ UnsupportedMethod
   ├─ PasswordError
   ├─ AuthenticationError
   ├─ FilenameEncodingError
   ├─ PathSecurityBlocked
   ├─ ResourceLimit
   ├─ BackendFailure
   ├─ UnknownBackendError
   └─ UnknownArchiveError
```

具体的なEnum / Error Catalogは実装時に確定する。

「部分的に壊れている」「完全に壊れている」をBackend Evidenceから判断できる場合は区別するが、判断不能なCaseを無理にどちらかへ分類しない。

---

## 4. Error Code Model

User-facing MessageとStable Error Code、Backend固有Errorを別Fieldとして扱う。

```text
User Message
LhaForge Error Code
Backend Result / Error Code
Raw Backend Message
```

LhaForge Error CodeのNamespace / Numberingは実装開始時にCatalog化し、一度Public Releaseで意味を割り当てたCodeを別用途へ再利用しない。

例として`LF-ARC-*`、`LF-ENC-*`、`LF-BKD-*`等の分類は候補とするが、現時点で番号体系をWire / Public Contractとして固定しない。

Loggingの`EventId`とUser-facing `ErrorCode`は同一概念として扱わない。1つのErrorに複数Log Eventが関連することを許容する。

---

## 5. Summary First UI

初期表示では、少なくとも次を確認できるようにする。

- Operation
- Overall Result
- Success / Failed / Skipped / Unknown件数
- Primary LhaForge Error Code
- User-facing Summary
- Error / Warning Entry List
- 詳細表示への入口
- Log Copy / Save
- Close

概念例:

```text
アーカイブを完全には解凍できませんでした

結果
  成功       1,247
  失敗           3
  不明           1

エラーコード
  LF-ARC-xxxx

概要
  一部のデータを正常に読み取れませんでした。

[エラー・警告のみ表示]

ファイル・フォルダー        結果        エラーコード
data01.bin                  失敗        LF-ARC-xxxx
image.jpg                   失敗        LF-ARC-xxxx
unknown.dat                 不明        LF-ARC-xxxx

[詳細を表示]

[ログをコピー] [ログをファイルとして保存 v] [閉じる]
```

通常はError / Warning / Unknownを優先表示し、成功Entryを大量に前面表示しない。

---

## 6. Detail View

詳細表示では、必要に応じて次を確認可能にする。

- Full Entry Result
- Selected Entry Path
- Selected Entry Message
- Backend ID / Version
- Backend Result
- Raw Backend Message
- Operation ID / Correlation ID
- LhaForge Error Code
- OS / HRESULT / NTSTATUS等、存在する追加Error
- Raw Backend Log

Entry数が大きい場合はVirtual List / Lazy Renderingを利用し、全Row用UI Objectを一括生成しない。

現行`CLogListDialog`が持つVirtual ListView、Sort、選択EntryのMessage / Path表示、Resize機構は再利用候補とする。ただし新UI要件を妨げる場合に旧Dialog構造へArchitectureを固定しない。

---

## 7. Window Size and Resize Policy

### 7.1 Initial width

横幅は現行Result / Log UI相当をBaseline候補とする。

固定Pixel値へ直結させずDPI Scaleを考慮し、現在表示するMonitorのWork Areaを超えないようClampする。

最終Preferred WidthはUI実装時に実機で決定する。

### 7.2 Initial height

初期高さは、Taskbar等を除いた現在MonitorのWork Area高さを基準にする。

初期候補:

```text
InitialHeight = WorkAreaHeight * 0.65
```

ただしMinimum / Maximum Boundを適用する。

### 7.3 Minimum size

Userは自由にResize可能とするが、主要Controlが重なる・Buttonが操作不能になるサイズより小さくできないようMinimum Tracking Sizeを設定する。

Web UIでいう`min-width` / `min-height`相当の制約である。

### 7.4 Maximum / maximize

Maximize Buttonを提供する。

Maximize時もSummary、List、Detail Pane、Buttonsが正しく追従し、Layoutが崩れないことを必須とする。

Modal Result WindowではMinimize Buttonは必須としない。

### 7.5 Scrolling

Entry数、Log行数、Message長に応じてWindow本体を無制限に拡大せず、List / Detail / Log領域をScroll可能にする。

---

## 8. Log Copy

Button文言:

```text
ログをコピー
```

既定ではHuman-readableな簡易DiagnosticをClipboardへCopyする。

最低候補:

```text
LhaForge Version
Timestamp
Operation
Overall Result
LhaForge Error Code
Archive Format
Backend ID / Version
Success / Failed / Skipped / Unknown count
User-facing Summary
主要Error Entry
```

Full Path等のPotentially Sensitive MetadataはLogging / Privacy Policyに従う。

---

## 9. Log Save

Button文言:

```text
ログをファイルとして保存 v
```

Drop-down候補:

```text
簡易ログを保存...
詳細ログを保存...
```

Save Asで扱うFile Type:

```text
Text File (*.txt)
Log File  (*.log)
```

既定候補:

```text
簡易ログ -> .txt
詳細ログ -> .log
```

UserがSave AsでExtensionを選択できることを許容する。

### 9.1 File name

既定File Name:

```text
LhaForge-{Operation}-{YYYYMMDD}-{HHMMSS}.{ext}
```

例:

```text
LhaForge-Extract-20260809-152245.log
LhaForge-Test-20260809-152245.log
```

Archive File Nameは長さ、禁止文字、Unicode、Privacyを考慮し既定File Nameへ含めない。

Collision時はSuffixを追加する。

```text
LhaForge-Extract-20260809-152245-2.log
```

---

## 10. Detailed Diagnostic

詳細LogはSupport / Developer向けとし、取得可能な範囲で次を含める。

```text
Application Version
Build ID
Git Commit
Architecture
Timestamp + UTC Offset
Operation ID
Correlation ID

Operation
Archive Format
Backend ID
Backend Version
Backend Architecture
Backend Hash (available when known)

Overall Result
LhaForge Error Code
OS Error / HRESULT / NTSTATUS (when present)
Entry Result Records

Raw Backend Log

Exception Code
Exception Module
Module Base
Exception Address
RVA
Stack Trace (when available)
Source File / Line (when available)
```

### 10.1 Source line policy

`source.cpp:line`をRuntime Error診断の必須情報にはしない。

Release Optimization、PDB非配置、External DLL Error等ではSource Lineを取得できないため、次を優先して残す。

```text
Build ID / Commit
Module
RVA
Exception Code
Stack Trace (when available)
Raw Backend Log
```

対応PDBが存在する場合は、後からSource File / LineへSymbolicateできる。

Source File / Lineを安全に取得できるCaseではAdditional Diagnosticとして保存してよい。

---

## 11. Raw Backend Log

Raw Backend Logは捨てない。

ただしUser-facing Summaryと混在させず、Detail / Saved Diagnosticから確認できるようにする。

```text
User-facing Summary
        |
        +--> Structured Result
        |
        `--> Raw Backend Log
```

External DLLが返したTextはEncoding BoundaryでUnicodeへ変換し、Untrusted Text Sanitizationを行う。

Raw Backend Log自体にPassword等が含まれる可能性があるBackendについては、Adapter側でRedaction / Handling Policyを持つ。

---

## 12. Encoding Error Separation

Filename Encodingの自動判定失敗、Ambiguous Encoding、Manual Override可能状態をArchive Corruptionとして表示しない。

例:

```text
FilenameEncodingAmbiguous
FilenameEncodingOverrideAvailable
```

は、

```text
ArchiveCorrupt
CRCError
DataError
```

とは別Reasonとする。

閲覧 / Preview / Extractで共通Filename Decode Policyを利用し、表示上の文字化けとArchive Data破損を混同しない。

---

## 13. Test / Extract / Other Operation Sharing

Result ModelはOperationごとに別実装しない。

```text
Operation Result Model
├─ List
├─ Test
├─ Extract
├─ Create
└─ Other Archive Operation
```

User-facing Caption / SummaryだけをOperationに合わせる。

Test例:

```text
アーカイブの検査が完了しました
正常: 1247
問題: 3
```

Extract例:

```text
解凍が完了しましたが、一部のファイルを解凍できませんでした
成功: 1247
失敗: 3
```

---

## 14. Security and Privacy

Diagnostic ExportはLocal Support機能であり、Secretを収集する理由にはしない。

禁止:

- Password
- Encryption Key
- Token
- Credential
- `.env`内容
- User File内容

Potentially Sensitive:

- Full Path
- File Name
- Archive Entry Name
- User Name
- Network Share

詳細LogでもSecretは禁止する。

Full Path等を含めるAdvanced Diagnostic Modeを設ける場合はDefault Offとし、保存 / Copy時にUserが認識できるようにする。

---

## 15. Performance Requirements

- Entry数でWindow初期Heightを増加させない。
- Large Entry ListはVirtualized / Lazy表示する。
- Raw Log全体を毎Paintで再整形しない。
- Summary countはOperation Result生成時に集計する。
- Debug / Trace無効時に高CostなDiagnostic文字列を常時生成しない。
- Maximize / Resize中にArchive Dataを再Scanしない。

---

## 16. Legacy Reuse Policy

現行`CLogDialog` / `CLogListDialog`の機能はBaselineとして調査する。

再利用候補:

- Resizable Dialog
- Virtual ListView
- Sort
- Selected Entry Detail
- Existing Result conversion

ただしv1.7.xのResult Model、Stable Error Code、Summary First、Diagnostic Exportを旧Dialogの制約に合わせて弱めない。

---

## 17. Open Items

- Exact Preferred Width
- Minimum Tracking Size
- Work Area HeightのMinimum / Maximum Clamp
- Window Size / PositionをSessionまたはConfigへ保存するか
- Stable Error Code Catalog
- Error / Warning Filterの初期条件
- Detail PaneのLayout
- Simplified / Detailed Logの最終Field Set
- Full Pathを含むDiagnostic Mode
- Crash DumpをDiagnostic UIから案内するか
- Existing Dialog再利用範囲
