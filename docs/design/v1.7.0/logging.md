# LhaForge v1.7.0 Logging Design

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Integration branch: `main-osamix`
- Development branch: `develop-v1.7.0`
- Scope: Application / Archive Backend / LegacyHost / Installer / Updater / Migration / Shell / Configuration / Security

Related documents:

- `architecture.md`
- `directory-layout.md`
- `backend.md`
- `archive-operations.md`
- `archive-result-ui.md`
- `migration.md`
- `installer.md`
- `security.md`
- `performance.md`
- `signing.md`
- `encoding.md`

---

## 1. Purpose

LhaForge v1.7.xでは、Application、Archive Backend、LegacyHost、Installer、Updater、Migration、Shell Integration等に分散する診断情報を、共通のLogging Architectureで扱う。

目的は単に大量の文字列をFileへ出力することではない。

次を実現する。

1. 問題発生時に「何が・どこで・なぜ失敗したか」を追跡できる。
2. External DLL / LegacyHost / Built-in Backendの選択理由を診断できる。
3. Installer / Migration / UpdateのLifecycle Operationを後から説明できる。
4. Security Eventを通常のOperation Eventと区別できる。
5. Windows Event LogとFile Logを独立して利用できる。
6. Debug / Traceを利用しても通常OperationのPerformanceを大きく損なわない。
7. Password、Token、`.env`内容等のSecretをLogへ記録しない。
8. Signed / Unsigned Releaseのどちらでも同じLogging Architectureを利用できる。
9. Log機能のFailureが、通常の圧縮・展開処理を不必要に停止させない。

---

## 2. Non-Goals

本設計では次を目的としない。

- User File内容の記録
- Archive Entry内容の記録
- PasswordやCredentialの記録
- Telemetry / Analyticsの外部送信
- Cloud Loggingの標準搭載
- LogをLifecycle Journalの代替にすること
- すべてのFile OperationをInfo Levelで逐一記録すること
- External DLLが返す文字列を無加工で記録すること

v1.7.0では、Loggingは基本的にLocal Diagnostics用途とする。

---

## 3. Architecture

共通Logging Coreを設ける。

```text
Subsystem
   │
   │ Structured Log Event
   ▼
Logging Core
   │
   ├─ Level / Component Filter
   ├─ Redaction / Sanitization
   ├─ Queue / Backpressure
   ├─ Context Enrichment
   │
   ├─ FileLogSink
   └─ WindowsEventLogSink
```

各SubsystemがFileへ直接`fprintf`等で書き込む構造にはしない。

Application側は共通InterfaceへStructured Eventを渡し、出力形式、Rotation、Event Log Mapping、Redaction等はLogging Core側で処理する。

---

## 4. Log Level

LhaForge内部では次の9 Levelを定義する。

高Severityから低Severity / 高Verbosityの順とする。

| Rank | Level | 日本語 | 用途 |
| ---: | --- | --- | --- |
| 1 | Emergency | 緊急 | Application / Lifecycle全体が継続不能な重大状態 |
| 2 | Alert | 警報 | 即時対応が必要な重大異常 |
| 3 | Critical | 致命的 | ComponentまたはOperationが継続不能 |
| 4 | Error | エラー | Operation失敗、明確な機能Failure |
| 5 | Warning | 警告 | 継続可能だが異常またはFallbackが発生 |
| 6 | Notice | 注意 | 通常より重要な状態変化、管理上知る価値があるEvent |
| 7 | Info | 情報 | 通常Operationの開始・終了・主要Decision |
| 8 | Debug | デバッグ | 「なぜそのDecisionになったか」を調査する情報 |
| 9 | Trace | トレース | 「どの順序で処理したか」を追う詳細情報 |

### 4.1 Level Filter

Sinkごとに独立した最低Severity / 最大Verbosityを設定可能とする。

例えば`Info`を設定した場合は、次を出力する。

```text
Emergency
Alert
Critical
Error
Warning
Notice
Info
```

`Debug`なら上記にDebugを加え、`Trace`なら全Levelを出力する。

UI上では「Minimum level」という表現だけでは向きが分かりづらいため、実装時には「記録する詳細度」等の表示も検討する。

---

## 5. Initial Default Policy

v1.7.0初期Default候補は次とする。

```text
File Log
    Enabled: Yes
    Level: Info

Windows Event Log / Operational
    Enabled: Yes when provider/channel is registered
    Level: Notice

Debug / Trace
    Default: Off
```

Windows Event Log ProviderがInstaller等により登録されていない環境では、Event Log Sinkが利用できないこと自体をApplication Failureにしない。

File Logは通常診断の主Sinkとする。

Windows Event Logは重要Event中心とし、通常処理の詳細で大量に埋めない。

---

## 6. Structured Log Event

内部Log Eventは文字列だけではなく、概念的に次のDataを持つ。

```text
LogEvent
├─ Timestamp
├─ Level
├─ EventId
├─ Component
├─ ProcessId
├─ ThreadId
├─ OperationId
├─ CorrelationId
├─ BackendId        optional
├─ Message
├─ ErrorCode        optional
├─ Fields[]         optional
└─ SecurityFlags[]  optional
```

### 6.1 Timestamp

内部では曖昧にならないTimestampを扱う。

File Logでは、少なくとも次を識別可能とする。

- 日付
- 時刻
- Millisecond程度の精度
- UTC OffsetまたはUTC

最終的なText Encoding / Timestamp表現は`encoding.md`と実装PoCで確定する。

### 6.2 OperationId

圧縮、展開、Test、Installer、Migration等のOperation開始時に一意なOperation IDを発行する。

例:

```text
Extract operation
OperationId = 7f...
```

これにより、複数Operationが同時に動いた場合でも関連Eventを追跡できる。

### 6.3 CorrelationId

複数ProcessにまたがるOperationではCorrelation IDを利用する。

例:

```text
LhaForge.exe
    │ CorrelationId
    ▼
LhaForgeLegacyHost.exe
    │
    ▼
x86 External DLL
```

Installer UI → Elevated Core、Updater → Installer Core等でも同じ考え方を利用できる。

---

## 7. Components

最低限、次のLogical Componentを定義する。

```text
App
UI
Archive
Backend
ExternalDLL
BuiltIn
LegacyHost
Security
Configuration
Encoding
Installer
Updater
Migration
Uninstaller
Shell
FileSystem
Logging
```

Component名はEvent IDと独立させる。

新しいComponent追加時にLog File形式やWindows Event Providerを作り直さなくてよい構造とする。

---

## 8. Event ID Namespace

Event IDはSubsystemごとにRangeを分ける。

| Range | Area |
| --- | --- |
| 1000-1999 | Application / UI |
| 2000-2999 | Archive / Backend / External DLL |
| 3000-3999 | Installer / Updater / Uninstaller |
| 4000-4999 | Migration |
| 5000-5999 | Security |
| 6000-6999 | LegacyHost |
| 7000-7999 | Configuration / Encoding |
| 8000-8999 | Shell Integration |
| 9000-9999 | Reserved / future use |

一度Public Releaseで意味を割り当てたEvent IDは、別の意味へ再利用しない。

具体的なEvent Catalogは実装開始時に別表またはSource定義として管理する。

例:

```text
2001 Backend selected
2002 Backend rejected by capability
2003 External DLL load failed
3001 Install started
3002 Install completed
4001 Migration started
4002 Migration rollback started
5001 Unsafe archive path blocked
6001 LegacyHost started
6002 LegacyHost disconnected unexpectedly
```

番号は現時点では例であり、実装時にCatalogを確定する。

---

## 9. Windows Event Log Mapping

LhaForge内部の9 LevelをWindows Event Logへ次のようにMappingする。

| LhaForge Level | Windows Level |
| --- | --- |
| Emergency | Critical |
| Alert | Critical |
| Critical | Critical |
| Error | Error |
| Warning | Warning |
| Notice | Information |
| Info | Information |
| Debug | Verbose |
| Trace | Verbose |

Windows側のLevelへMappingしても、Structured Fieldとして元の`LhaForgeLevel`を保持する。

これによりEmergency / Alert / Criticalの区別を失わない。

---

## 10. Windows Event Log Provider / Channels

ConceptualなProvider名は次とする。

```text
Provider: LhaForge
```

Channel候補:

```text
Applications and Services Logs
└─ LhaForge
   ├─ Operational
   └─ Debug
```

### 10.1 Operational

通常有効。

主に次を記録する。

- Critical / Error
- Warning
- Notice
- 重要なSecurity Event
- Installer / Migration / Updateの主要状態変化

Infoを大量出力しない。

### 10.2 Debug

既定無効または高Verbosity時のみ利用する。

- Debug
- Trace
- 詳細なBackend Probe
- LegacyHost IPC診断

Windows Event LogへDebug / Traceを常時大量出力しない。

### 10.3 Provider Registration

Custom Provider / Channelの登録はInstaller-managed System Integrationとして扱う。

登録に管理者権限が必要な場合はInstaller / Repair等のElevated Coreが担当する。

LhaForge.exe本体を管理者実行する理由にはしない。

Provider未登録、破損、Event Log書込Failureは通常のArchive Operationを停止させない。

---

## 11. File Log Layout

通常Application Logは次を基本とする。

```text
%LOCALAPPDATA%\LhaForge\Logs\
```

Conceptual layout:

```text
Logs\
├─ LhaForge.log
├─ LegacyHost.log
└─ Shell.log
```

ただし、複数Processが同一Fileを競合して書き込まないよう、実装時にはProcess別StreamまたはLogging Broker方式を評価する。

### 11.1 Lifecycle Log

Machine-wide Installer / Migration / Uninstallは、Runtime LogとLifecycle記録のOwnershipが異なる。

候補:

```text
%ProgramData%\LhaForge\Logs\Lifecycle\
├─ installer.log
├─ migration.log
└─ uninstall.log
```

Machine Logを利用する場合はACLを明示し、一般Userへ不用意にPath情報等を公開しない。

Setup bootstrap等、Elevation前の初期Logは安全なUser Temp等へ作成し、Lifecycle Core初期化後に必要な範囲だけ正式Logへ統合する方式を検討する。

最終Path / ACLはInstaller PoCで確定する。

---

## 12. File Log Format

Logging Core内部はStructured Dataを保持する。

v1.7.0の標準File Logは、人間が直接読みやすく、Toolでも解析可能なLine-oriented形式を基本候補とする。

概念例:

```text
2026-07-28T22:15:32.123+09:00 [INFO] [Archive] [2001] op=... backend=7zip64 Backend selected
```

必須要件:

- 1 Eventを明確に区切れる
- Timestampを機械的に解析できる
- Level / Component / Event IDを識別できる
- Operation IDを追跡できる
- Message内の改行やControl Characterを安全にEscapeできる
- Untrusted StringによるLog Injectionを防止する

JSON Lines等のStructured Exportは将来Optionとして検討可能だが、v1.7.0必須要件にはしない。

---

## 13. Encoding

新しいLhaForge管理LogはUnicode前提とする。

`encoding.md`に従い、File LogはUTF-8 BOMなしをDefaultとし、Legacy CP932 Logを新規Architectureの内部標準にはしない。

改行、Legacy LogのRead Compatibility、外部DLL文字列の変換Policyも`encoding.md`と共通化する。

External DLLからANSI文字列を受け取る場合は、DLL BoundaryでUnicodeへ変換してからLogging Coreへ渡す。

変換失敗自体も診断可能にするが、Raw byte列を無制限にLogへ書き出さない。

---

## 14. Sensitive Data Classification

Logへ渡すDataを少なくとも次の3区分で考える。

### 14.1 Safe Operational Metadata

通常Logへ記録可能。

例:

- Backend ID
- Backend Architecture
- Version
- Capability名
- Error Code
- Operation種別
- File件数
- 処理時間
- Size等の集計値

### 14.2 Potentially Sensitive Metadata

既定では必要最小限にする。

例:

- Full Path
- File Name
- Archive Entry Name
- User Name
- Command Line
- Environment Variable名
- Network Path
- Share名

これらは「内容」ではなく名前だけでも機密情報になり得る。

### 14.3 Secret

Levelに関係なく記録禁止。

例:

- Password
- Passphrase
- API Token
- Access Token
- Cookie
- Credential
- Private Key
- Secret Key
- `.env`内容
- Archive File内部のSecret内容

Debug / TraceでもSecretそのものを記録しない。

---

## 15. Path / File Name Logging Policy

Operational Logでは、Full Pathを無条件記録しない。

例えばSecurity Block Eventでは、次のような情報を優先する。

```text
Unsafe archive entry blocked
Reason = PathTraversal
EntryIndex = 42
```

必要なら安全にSanitizeしたFile Name、Relative Path、一方向Hash等を追加できる。

### 15.1 Diagnostic Path Detail

将来、Troubleshooting用にFull Path等を含めるOptionを提供する場合は、次を満たす。

- Default Off
- UserへPrivacy Riskを表示
- Secret内容は依然として記録禁止
- Session-onlyまたは自動解除を優先
- Diagnostic Bundle作成時に再確認可能

「Debug LevelをONにしただけでFull Path / Secretまで全部出る」仕様にはしない。

---

## 16. Untrusted Text Sanitization

External DLL、Archive Entry、File Name等から取得したStringはUntrusted Inputとして扱う。

Logging前に少なくとも次を処理する。

- CR / LFのEscape
- NUL等Control Characterの扱い
- 極端に長い文字列のTruncate
- Invalid Unicodeの安全な変換
- Terminal / Viewerを誤動作させるControl Characterの抑制

External DLLのError MessageをそのままFormat Stringとして利用しない。

Log Injectionによって偽のLevel / Timestamp / Eventを作れる形式にしない。

---

## 17. Archive Operation Logging

通常の圧縮 / 展開では、Info LevelでFile単位の記録を大量に行わない。

Info例:

```text
Archive operation started
Backend selected
Input count = 182
Excluded count = 4
Archive operation completed
Elapsed = ...
```

Debugでは選択理由を記録できる。

```text
External x64 backend rejected: ExactInputSet capability missing
External x86 backend accepted
```

Traceではより詳細なOperation Sequenceを記録できるが、既定Offとする。

### 17.1 Exclusion Rule

`.git` / `.env`等の除外時に、Secret内容をLogへ記録しない。

既定では次のような集計情報を優先する。

```text
Input filter applied
RuleSet = DefaultSensitiveFiles
Excluded = 12
```

必要な場合でもRule ID / Pattern種別までとし、除外された`.env`の内容等は絶対に記録しない。

### 17.2 Operation Result / Diagnostic Export

User-facing Archive Result / Error UIとFile Logは別の責務とするが、Structured Operation Contextを共有する。

```text
Structured Operation Result
        ├─ Summary First UI
        ├─ Simplified Diagnostic
        ├─ Detailed Diagnostic
        └─ Raw Backend Log
```

`ErrorCode`と`EventId`は同一概念として扱わない。

- `ErrorCode`: User / Supportが同じFailure classを識別するStable Code
- `EventId`: Logging上の個々のEvent種別

Detailed Diagnosticでは、取得可能な範囲でBuild ID、Commit、Backend、Operation ID、Exception Code、Module / RVA、Raw Backend Log等を含める。

Source File / Lineは取得可能な場合の追加情報とし、Release Diagnostics成立の必須条件にはしない。

Copy / SaveのUser-facing Policy、Window Size、簡易 / 詳細LogのFieldは`archive-result-ui.md`に従う。

---

## 18. Backend Logging

Backend Probeでは次を診断可能にする。

- Backend ID
- Type: External x64 / External x86 / Built-in
- Architecture
- DLL Version
- Probe State
- Capability
- Rejection Reason
- Load Error
- Compatibility Error

External DLLのFull PathはPotentially Sensitive Metadataとして扱う。

Operational Eventでは、DLL File名やBackend IDだけで十分な場合はFull Pathを出さない。

---

## 19. LegacyHost Logging

LegacyHostは別Processであるため、親OperationとのCorrelationを維持する。

最低限記録可能にするEvent:

- Host start / stop
- Protocol version
- Request開始 / 終了
- Timeout
- Cancel
- Pipe切断
- DLL load failure
- Host crash / abnormal termination
- Fault quarantine

IPC PayloadそのものをTraceで丸ごとDumpしない。

File List、Password、Archive Entry等のDataが含まれ得るためである。

---

## 20. Security Event Logging

Security PolicyがOperationをBlockした場合は、原因を診断可能にする。

例:

- Path Traversal
- Absolute Path
- UNC / Device Path
- ADS
- Reserved Name
- Reparse Point Policy
- Archive Bomb / Resource Limit
- Invalid DLL Path
- Invalid IPC Request
- Signature validation failure when signing is enabled

Security Eventは5000番台を使用する。

ただし「Securityだから全部Critical」にしない。

例:

```text
危険なArchive Entryを正常にBlockした
    Warning / Notice候補

Security Guardそのものが初期化不能
    Critical候補
```

Attack-controlled StringをWindows Event Logへ大量出力させるDoSにも注意する。

---

## 21. Installer / Updater / Migration Logging

Lifecycle Operationでは主要Phaseを記録する。

例:

```text
Detect
Inventory
Plan
Preflight
Backup
Stage
Apply
Validate
Commit
Cleanup
Rollback
```

記録対象:

- Operation ID
- Source Version
- Target Version
- Mode
- Phase
- Result
- Error Code
- Rollback開始 / 結果
- Repair判断

User-owned Fileの内容やSecretは記録しない。

---

## 22. Log and Journal Separation

**LogとLifecycle Journalは別物とする。**

### Log

目的:

- Troubleshooting
- Diagnostic
- User / Developerが状況を理解する

Log書込Failureは通常Application Operationを停止させない。

### Journal

目的:

- Migration / Installer Transaction State
- Rollback
- Resume / Recovery
- Commit判定

Journalは安全なLifecycle処理に必要なStateであり、必要なCheckpointを永続化できない場合は、そのLifecycle Operationを継続してはならない場合がある。

```text
Logging failure
    ≠ Transaction state failure
```

Logを解析してRollback Stateを推測するArchitectureにはしない。

---

## 23. Performance Architecture

Loggingによって圧縮 / 展開Performanceを大きく落とさない。

### 23.1 Queue

通常Log EventはBounded Queueを経由してSinkへ非同期出力する方式を基本候補とする。

```text
Worker Thread
    │
    ▼
Bounded Log Queue
    │
    ▼
Log Writer
```

Queueを無制限に成長させない。

### 23.2 Backpressure / Drop Policy

高負荷時にはSeverityを考慮する。

原則:

- Emergency / Alert / Critical / Errorを優先
- Debug / Traceを最初に抑制可能
- Infoも大量EventではSampling / Aggregationを検討
- Dropが発生した場合、後で件数をSummary Eventとして記録

例:

```text
Logging queue pressure: 1250 Trace events omitted
```

高Severity Eventが必ずMemory無制限増加を起こす設計にもしてはならないため、最終的なQueue / Emergency fallbackはPoCで検証する。

### 23.3 Flush

毎EventでDisk Flushしない。

一方、Critical / Error、Lifecycleの重要境界等では早期Flushを検討する。

Transaction durabilityはLogging FlushではなくJournal設計で保証する。

### 23.4 Per-file Logging

大量ArchiveでFileごとにInfo Eventを出さない。

File単位Detailが必要な場合はDebug / Traceとし、Aggregationを優先する。

---

## 24. Rotation

File Logは無制限に増加させない。

少なくとも次を設定可能なArchitectureとする。

- Maximum file size
- Retained generations
- Maximum age
- Total storage limit

v1.7.0 Default値はPoCで決める。

初期候補としては、Runtime LogをSize-based Rotationし、複数世代を保持する。

Lifecycle Logは障害解析価値が高いためRuntime LogとRetentionを分離できるようにする。

Rotation中のFailureでApplication Operationを停止させない。

---

## 25. Cleanup / Uninstall

LogはUser / Diagnostic Dataとして扱う。

Repairでは原則削除しない。

Uninstallでは既定Preserveとし、ユーザーが「ログ・キャッシュ等を削除」を明示選択した場合に削除対象とできる。

Machine Lifecycle Logについても同様にOwnershipを確認する。

Unknown Log Fileや他Version / 他UserのDataをDirectory丸ごと削除しない。

---

## 26. Failure Handling

Logging Core自身のFailureを再帰的にLoggingし続けない。

例:

```text
FileLogSink write failed
    ↓
FileLogSinkへ同じErrorを書こうとする
    ↓
無限再帰
```

を防ぐ。

Fallback候補:

```text
File Sink failure
    ↓
Event Log Sink available?
    ├─ Yes → 最小Event
    └─ No  → Process内Diagnostic stateのみ
```

逆方向も同様。

両SinkのFailureだけで通常Archive OperationをFailure扱いにしない。

ただしLifecycle Journal FailureはSection 22のPolicyに従う。

---

## 27. Crash Diagnostics

Unhandled Exception / Process Crash時に、可能な範囲で次を残す。

- Process / Component
- Application Version
- Build ID / Commit
- Operation ID / Correlation ID
- Last Phase
- Exception / Error Code
- Faulting Module
- Module Base
- Exception Address
- RVA
- Stack Trace（安全に取得可能な場合）
- Source File / Line（Symbol情報から取得可能な場合）

Source File / Lineを必須情報にしない。

Release Optimization、PDB非配置、External DLL Error等ではその場でSource Lineを取得できないため、

```text
Build ID / Commit
Module
RVA
Exception Code
Stack Trace
Raw Backend Log
```

を優先Diagnosticとする。対応PDBが存在する場合は後からSymbolicateできる。

Crash Handlerで複雑なLogging処理や大量Allocationを行わない。

MinidumpはMemory内のPassword、File Content、Token等を含む可能性があるため、v1.7.0で標準自動生成するかは別途検討する。

Diagnostic Dumpを導入する場合は、Privacy / Security Policyを明示する。

---

## 28. Configuration Model

Config File形式自体は`encoding.md`およびConfiguration設計で確定するが、概念的には次を持つ。

```text
Logging
├─ File
│  ├─ Enabled
│  ├─ Level
│  ├─ Rotation
│  └─ Retention
│
├─ EventLog
│  ├─ Enabled
│  ├─ Level
│  └─ DebugChannelEnabled
│
└─ Diagnostics
   ├─ IncludePathDetails
   └─ TraceEnabled
```

`IncludePathDetails`等のSensitive Diagnostic OptionはDefault Offとする。

Secret Loggingを有効化するOptionは設けない。

---

## 29. UI Direction

通常User向けOptionでは、設定を過度に複雑にしない。

例:

```text
ログ
  [x] ファイルへ記録する
      詳細度: 情報

  [x] Windows イベントログへ重要な情報を記録する

  [ ] デバッグログを有効にする
```

Advanced / Diagnostic UIでは必要に応じてSinkごとのLevel、Retention等を設定できる方向とする。

Traceは通常設定から誤って常時有効になりにくいUIとする。

---

## 30. Diagnostic Bundle

将来的に「診断情報をまとめて保存」を提供する場合は、Logをそのまま無条件ZIP化しない。

次を実施する。

1. 対象Logを列挙
2. Sensitive Data Policyを再適用
3. Userへ含まれる情報の注意を表示
4. 必要ならPath情報を追加Redact
5. User確認後にBundle生成

`.env`、Config内Credential、Archive内容等を自動収集しない。

---

## 31. Security Requirements

Logging実装自体をAttack Surfaceにしない。

必須要件:

- Format String Injectionを防止
- Log Injectionを防止
- Untrusted Stringの長さ制限
- Directory TraversalをLog File名へ反映しない
- Log Directory / File ACLを考慮
- Symlink / Reparse Pointを利用したLog File置換攻撃を考慮
- Elevated ProcessからUser-controlled任意PathへLogを書かない
- Secretを記録しない
- Event FloodingへのRate Limit / Aggregationを検討

Installer / Elevated CoreのLog Pathは特にSecurity Review対象とする。

---

## 32. Compatibility

v1.6.7の既存Log UIやError表示の使い勝手を可能な範囲で維持するが、新Logging Coreへ内部的に統合する。

User-facingな「処理結果表示」とPersistent Diagnostic Logは同一概念ではない。

Legacy External DLLが独自Logを出力する場合、そのLogのOwnershipはExternal Component側にある。

LhaForgeが第三者DLLのLog Fileを勝手に削除・書換しない。

---

## 33. Testing

少なくとも次をTestする。

### Functional

- Level Filter
- Sink独立設定
- Event ID
- Operation / Correlation ID
- Rotation
- Multi-process

### Security

- CRLF Log Injection
- NUL / Control Character
- Extremely long File Name
- Malformed Unicode
- Secret Redaction
- `.env`等の内容がLogへ入らないこと
- Reparse / Symlinkを利用したLog Path攻撃

### Performance

- 数十万Entry Archive
- Trace大量発生
- Queue saturation
- Slow disk
- Event Log unavailable

### Failure

- Disk full
- Access denied
- Log directory missing
- File locked
- Event provider missing
- Rotation failure

Logging Failureが本来成功すべきArchive Operationを不要に失敗させないことを確認する。

---

## 34. Open Items

実装前に次をPoC / Reviewで確定する。

- File Logの正式Encoding / BOM / newline
- Runtime LogのDefault Rotation size / generation / retention
- Lifecycle Logの最終PathとACL
- Multi-process File Sink方式
- Windows Event Log Provider manifest方式
- Operational / Debug ChannelのDefault設定
- Crash dump方針
- Diagnostic Bundleのv1.7.0搭載有無
- Full Path Diagnostic OptionのUI
- Event Catalogの正式割当

---

## 35. Design Principle

v1.7.xのLogging原則は、

> 必要なときに十分な原因追跡ができる情報を残しながら、Userの機密情報・Security・Performanceを犠牲にしない

ことである。

さらに、

> Logは診断情報であり、Security BoundaryやTransaction Journalの代わりではない

ことをArchitecture上明確に維持する。
