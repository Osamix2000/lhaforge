# LhaForge v1.7.0 Archive Backend Design

* Status: Draft
* Target: LhaForge v1.7.x
* Baseline: LhaForge v1.6.7
* Scope: ArchiveManager / External x64 DLL / External x86 DLL + LegacyHost / Built-in Backend

Related ADR:

* ADR-0002: v1系外部DLL互換を維持する
* ADR-0003: x64本体とLegacyHostを採用する
* ADR-0004: Built-in BackendをFallbackとして持つ

Related design documents:

* `architecture.md`
* `archive-operations.md`
* `directory-layout.md`
* `ownership-matrix.md`
* `security.md`
* `performance.md`
* `signing.md`
* `zste-format.md`

---

## 1. Purpose

LhaForge v1.7.xでは、v1系の統合アーカイバDLLを正式なBackendとして維持しながら、x64本体、x86 LegacyHost、Built-in Backendを同一のArchiveManagerから扱う。

本設計の目的は、

> Archive Formatや拡張子ではなく、現在要求されているOperationを安全かつ正確に実行できるBackendを選択する

ことである。

v1.6.7の外部DLL文化は維持するが、DLLの存在だけを理由に利用したり、失敗後に無条件で別Backendへ再実行したりしない。

---

## 2. Design Principles

Backend設計では次を基本原則とする。

1. External DLLを第一級Backendとして維持する
2. x64 External DLLを第一候補とする
3. x86専用DLLはLegacyHost経由で維持する
4. Built-in BackendはFallbackと基本可用性を提供する
5. Backend選択はCapabilityベースで行う
6. Archive拡張子だけを信頼しない
7. Security PolicyをBackend固有実装へ委ねない
8. Backend障害が他BackendやUIへ不必要に波及しないよう分離する
9. Operation開始後のFallbackは副作用を考慮する
10. PerformanceのためにCorrectnessやSecurity Validationを省略しない
11. User-serviceableなExternal DLLをInstaller / Repairが無条件上書きしない
12. Built-in / Externalの違いをUIの基本操作へ露出させすぎない

---

## 3. High-Level Flow

```text
User Operation
      ↓
Operation Planner
      ↓
Operation Plan
      │
      ├─ Format / Logical Archive
      ├─ Requested Capabilities
      ├─ Final Input Set
      ├─ Destination Policy
      └─ Security Constraints
      ↓
ArchiveManager
      ↓
Backend Discovery / Candidate Build
      ↓
Capability / Compatibility / Policy Filter
      ↓
Backend Selection
      ↓
┌──────────────────────────────────────────┐
│ 1. External x64 Backend                  │
│ 2. External x86 Backend + LegacyHost     │
│ 3. Built-in Backend                      │
└──────────────────────────────────────────┘
      ↓
Preflight Validation
      ↓
Operation Execution
      ↓
Result / Progress / Diagnostics
```

Operation Plannerは「何をしたいか」を決定し、ArchiveManagerは「どのBackendで行うか」を決定する。

---

## 4. Backend Categories

### 4.1 External x64 Backend

64bit LhaForge本体から直接ロードする外部DLL。

基本配置:

```text
dll\x64\
```

特徴:

* v1系外部DLL文化を継承する
* User-serviceable
* LhaForge本体と独立して更新可能
* x86/x64 Process境界のIPCが不要
* DLLごとにAPI / Version / Capability差異がある

---

### 4.2 External x86 Backend

32bit専用外部DLL。

基本配置:

```text
dll\x86\
```

64bit本体へ直接ロードせず、`LhaForgeLegacyHost.exe` x86を経由する。

```text
LhaForge.exe x64
      │
      │ Named Pipe
      ▼
LhaForgeLegacyHost.exe x86
      │
      ▼
External DLL x86
```

External x86 BackendもExternal x64 Backendと同じBackend Modelへ変換し、Application LayerからはProcess Architecture差を可能な限り隠蔽する。

---

### 4.3 Built-in Backend

LhaForge管理下のLibraryを利用するBackend。

目的:

* External DLL未導入時の基本可用性
* External DLL非対応Capabilityの補完
* Legacy DLL障害時のFallback候補
* 将来のSafe Mode候補

Built-in BackendはExternal DLLを廃止するためのものではない。

---

## 5. Backend Adapter

External DLLはDLLごとにAPIが異なるため、ArchiveManagerから直接DLL固有APIを呼ばない。

```text
ArchiveManager
     ↓
IArchiveBackend
     ↓
Backend Adapter
     ├─ 7-Zip family adapter
     ├─ TAR family adapter
     ├─ UNLHA family adapter
     ├─ UNRAR family adapter
     ├─ Other legacy adapter
     └─ Built-in adapter
```

AdapterはBackend固有APIを共通Backend Modelへ変換する。

Adapterの責務:

* DLL API / Export差異の吸収
* Version判定
* Capability変換
* Error Code変換
* Progress変換
* Character Encoding境界処理
* Backend固有Option変換
* Thread-safety / Concurrency Policyの提供

UIやOperation PlannerへDLL固有APIを露出させない。

---

## 6. Backend Identity

Backendは表示名だけで識別しない。

内部では安定したBackend IDを持つ。

概念例:

```text
external.7zip.x64
external.7zip.x86
external.tar.x64
external.tar.x86
external.unlha.x64
external.unlha.x86
builtin.libarchive
```

実際の命名は実装時に確定するが、次を区別できることを要件とする。

* Backend Family
* Implementation
* Architecture
* Version
* Source / Ownership

DLLファイル名そのものを永続設定の唯一のIdentityとして使用しない。

---

## 7. Backend Descriptor

Discovery後のBackendは、概念的に次の情報を持つ。

```text
BackendDescriptor
├─ BackendId
├─ DisplayName
├─ BackendType
│  ├─ ExternalX64
│  ├─ ExternalX86
│  └─ BuiltIn
├─ AdapterFamily
├─ Architecture
├─ Version
├─ FilePath
├─ FileIdentity
│  ├─ Size
│  ├─ LastWriteTime
│  └─ Hash (必要時)
├─ SignatureMetadata (Optional)
├─ SupportedFormats
├─ Capabilities
├─ CompatibilityFlags
├─ ConcurrencyPolicy
├─ TrustState
└─ DiagnosticState
```

External DLLのAuthenticode署名は存在すればMetadataとして利用できるが、署名の有無だけで利用可否を決めない。

---

## 8. Capability Model

最低限、次のCapabilityを扱う。

### Basic Archive Operations

```text
Open
List
Test
Extract
Create
Update
Delete
```

### Archive Features

```text
PasswordRead
PasswordWrite
Encryption
AuthenticatedEncryption
CompressionMethod
CompressionProfile
MultiVolumeRead
MultiVolumeWrite
ArchiveComment
EntryComment
```

### Input / Output Control

```text
ExactInputSet
InputList
OutputDirectory
Progress
Cancel
```

### Metadata / Compatibility

```text
UnicodeFileName
UnicodeComment
Timestamp
FileAttributes
Symlink
Hardlink
ReparseMetadata
```

Capabilityは単なるBooleanだけで不足する場合があるため、必要に応じてLevelまたはDetailを持てる構造とする。

例:

```text
Encryption
├─ ZipCrypto
├─ AES128
├─ AES192
├─ AES256
└─ ZSTE-v1

CompressionMethod
├─ Deflate
├─ LZMA
└─ Zstandard

ZstandardProfile
├─ CompressionLevel
├─ MultiThread
├─ MaximumCompressionPreset
└─ FrameChecksum
```

`PasswordRead = true`だけでは、ZSTE v1のAuthenticated Encryptionを安全に扱えることを意味しない。Format / Encryption Construction / Argon2id `m` / `t` / `p` / Streaming Authenticationまで含むDetail Capabilityを持たせる。

---

## 9. ExactInputSet

圧縮対象除外機能の安全性を保証するため、`ExactInputSet`を重要Capabilityとして扱う。

`.git`、`.env`等を除外した場合、Backendへ渡すのはOperation Plannerが確定したFinal Input Setだけでなければならない。

```text
Input Tree
   ↓
Exclusion Rules
   ↓
Final Input Set
   ↓
Backend
```

次のようなBackend利用は禁止する。

```text
Final Input Setで.envを除外
       ↓
Backendへ親Directoryのみ渡す
       ↓
Backendが再Scan
       ↓
.envがArchiveへ混入
```

Filtered Createでは原則として、

```text
Create + ExactInputSet
```

を満たすBackendのみ候補とする。

BackendがResponse FileやInput List APIを持つ場合はAdapterが利用する。

正確なInput Setを保証できない場合、除外機能を無視して圧縮を続行しない。

---

## 10. Format Registry

Archive Format情報はBackend個別設定へ散在させず、Format Registryとして管理する。

概念情報:

```text
ArchiveFormat
├─ FormatId
├─ DisplayName
├─ Extensions
├─ CompoundExtensions
├─ ContentSignatures
├─ CreateSupport
├─ LogicalNameRules
└─ CandidateBackends
```

例:

```text
TAR.GZ
Extensions:
  .tar.gz
  .tgz

Logical name:
  source.tar.gz → source

ZSTE
Extensions:
  .zste
Content signature:
  ZSTE wire magic (exact bytes are frozen by the ZSTE specification)

TAR.ZSTE
Compound extension:
  .tar.zste
Logical name:
  package.tar.zste → package
```

Format Registryは、

* Backend候補生成
* Archive名を使った展開先Folder名
* Compound Extension判定
* UI Format選択

等で共用する。

---

## 11. Format Detection

### Create

新規圧縮ではユーザーが選択したFormatを正とする。

Output File NameのExtensionがFormatと矛盾する場合は、設定に応じて補正または確認する。

### Open / List / Test / Extract

既存ArchiveではExtensionをHintとして利用するが、Extensionだけで確定しない。

概念Flow:

```text
File name / extension
        ↓
Candidate formats
        ↓
Content / Backend probe
        ↓
Validated format
```

`.zip`という名前だから無条件にZIPとして信頼することはしない。

一方、すべてのBackendで毎回Archive全体をProbeするような高コスト実装も避ける。

Format DetectionはSecurity、Compatibility、Performanceのバランスを取る。

---

## 12. Discovery Phases

Backend Discoveryは段階的に行う。

### Phase 1: Registration

LhaForgeが知っているBackend Family / Adapterを登録する。

この段階ではExternal DLLが存在するとは限らない。

### Phase 2: File Discovery

指定されたBackend Directoryから候補DLLを検出する。

```text
dll\x64\
dll\x86\
```

Current Directoryや無関係なPATH Directoryを暗黙探索しない。

### Phase 3: Static Validation

可能な範囲でLoad前に確認する。

* File exists
* Regular file
* Expected location
* PE format
* Machine architecture
* Size sanity
* File identity

### Phase 4: Load / Probe

Adapterの管理下でLoadする。

* Safe DLL search policy
* Required Export
* API Version
* Initialization
* Version query
* Capability query / derivation

### Phase 5: Compatibility Evaluation

Loadできても利用可能とは限らない。

* Known incompatible version
* Missing required API
* Broken Unicode behavior
* Unsupported operation
* Known unsafe behavior
* Runtime test failure

等を評価する。

### Phase 6: Descriptor Cache

確定した情報をCache可能とする。

---

## 13. Backend State

Backendの状態を少なくとも次のように区別する。

```text
NotDiscovered
Discovered
InvalidFile
ArchitectureMismatch
LoadFailed
Incompatible
Unavailable
Usable
DisabledByUser
BlockedByPolicy
Faulted
```

単純な`available = true/false`だけにしないことで、UIとLoggingで原因を説明可能にする。

---

## 14. External DLL Loading

External DLLは明示的なTrust Boundaryとする。

ロード時は次を原則とする。

* Absolute Pathを使用する
* Current Directoryへ依存しない
* DLL Search Pathを制限する
* PE ArchitectureをLoad前に確認する
* Adapterが期待するDLL Familyか検証する
* 必須Exportを確認する
* Load / Unload lifecycleを管理する
* ErrorをWindows Error / DLL Error / Adapter Errorへ分類する

v1.6.7に存在する旧保護策を尊重しつつ、Current Directory変更に頼る方式から、より明示的なLoad PolicyへModernizeする。

---

## 15. External x64 Backend Execution

External x64 DLLはLhaForge本体Process内で動作するため、x86 LegacyHostよりOverheadは小さい一方、DLL障害が本体へ直接影響する可能性がある。

そのため、

* Operation前Validation
* Adapter Boundary
* Exception / Error Boundary
* Parameter Validation
* Return Value Validation
* Output Metadata Validation

を重視する。

将来、特定の高Risk DLLを別Processへ隔離する必要が生じた場合は別ADRで検討する。

---

## 16. LegacyHost Backend

x86 DLLはLegacyHostで実行する。

### Responsibilities

LegacyHost:

* x86 DLL Load
* API呼び出し
* Operation実行
* Progress取得
* Result / Error返却

LhaForge本体:

* UI
* Configuration
* Backend Selection
* Security Policy
* Operation Planning
* Result Policy

### IPC

Named Pipeを基本とする。

Archive DataそのものはIPCで転送しない。

```text
LhaForge.exe
     │ Control / Metadata
     ▼
Named Pipe
     │
     ▼
LegacyHost
     │ File I/O
     ▼
Filesystem
```

大量Entry ListはBatch化する。

### Lifecycle

Backend Policyに応じ、Application Session内でHostを再利用可能とする。

ただし、

* Host crash
* DLL crash
* Protocol error
* Timeout

時にはHostを破棄し、安全に再生成できる構造とする。

---

## 17. LegacyHost Protocol Versioning

本体とLegacyHostは別Binaryであるため、IPC Protocol Versionを明示する。

概念:

```text
ProtocolVersion
MessageType
RequestId
PayloadLength
Payload
```

要件:

* Unknown messageを拒否する
* Lengthを検証する
* Integer overflowを防ぐ
* Request / Responseを対応付ける
* Timeout / Cancelを扱う
* Protocol version mismatchを明示的にError化する

将来のv1.7.x更新で本体とLegacyHostのVersionが一時的にずれた場合も、無言で誤動作しない。

---

## 18. Built-in Backend

Built-in BackendはLhaForge管理下のLibraryをAdapter経由で利用する。

初期Target:

```text
ZIP
7z
TAR
gzip
bzip2
XZ
LZMA
Zstandard
RAR / RAR5 read
```

想定Operation:

| Format | List | Test | Extract | Create | Update |
|---|---|---|---|---|---|
| ZIP | Target | Target | Target | Target | Evaluate |
| 7z | Target | Target | Target | Target | Evaluate |
| TAR | Target | Target | Target | Target | Evaluate |
| gzip | Target | Target | Target | Target | N/A / Evaluate |
| bzip2 | Target | Target | Target | Target | N/A / Evaluate |
| XZ | Target | Target | Target | Target | N/A / Evaluate |
| LZMA | Target | Target | Target | Target | N/A / Evaluate |
| Zstandard | Target | Target | Target | Target | N/A / Evaluate |
| RAR / RAR5 | Target | Target | Target | No | No |

実Library選定後、Capability Matrixを実測して確定する。

RAR作成をBuilt-in Backendの必須要件にはしない。

---

## 19. Backend Candidate Construction

Operationごとに候補Backendを生成する。

入力:

```text
Operation Plan
├─ Format
├─ Operation
├─ Required Capabilities
├─ Security Requirements
├─ User Backend Policy
└─ Environment
```

出力:

```text
Candidate List
```

基本順位:

```text
External x64
External x86 + LegacyHost
Built-in
```

ただし優先順位よりRequired Capabilityを先に満たす必要がある。

例:

```text
ZIP Create + Filtered Input

External x64:
  Create = Yes
  ExactInputSet = No
  → Candidateから除外

External x86:
  Create = Yes
  ExactInputSet = Yes
  → Candidate

Built-in:
  Create = Yes
  ExactInputSet = Yes
  → Candidate

Selected:
  External x86
```

「x64だからCapability不足でも選ぶ」という判断はしない。

---

## 20. Selection Score / Policy

基本順位を維持しながら、将来の条件追加に耐えられるようSelection Policyを分離する。

概念的な判定順:

1. Required Format
2. Required Operation
3. Required Security / Exactness Capability
4. Backend State = Usable
5. User Disable / Policy Block
6. Compatibility Constraint
7. Architecture Priority
8. User Preference
9. Performance Hint

Security / Correctness条件をPerformanceやPreferenceより優先する。

---

## 21. User Backend Policy

通常ユーザーはBackendを意識しなくても利用できるよう、自動選択をDefaultとする。

一方、v1系では外部DLLを手動保守する文化があるため、Advanced Optionとして次を許容できる設計とする。

* Backendの有効 / 無効
* Format単位の優先Backend
* Operation単位の優先Backend
* Built-inを優先するTroubleshooting / Safe Mode
* Automaticへ戻す

ただしUser PreferenceがSecurity Requirementを上書きしてはならない。

利用不能なBackendを強制指定した場合は、安全でない実行ではなく明確なErrorとする。

---

## 22. Preflight

Backendを選択した後、Operation開始前にPreflightを行う。

### Common

* Backendが現在も利用可能か
* Input File / Directory状態
* Output Destination
* Required free spaceを推定可能な範囲で確認
* Required Capability
* Security Policy
* Cancellation state

### Create

* Final Input Set
* ExactInputSet保証
* Output file collision
* Password / Encryption support
* Multi-volume support

### Extract

* Archive openability
* Entry metadata取得可能性
* Destination root
* Extraction Path Policy
* Resource Budget

Preflightを通過する前に、可能な限りOutputへ副作用を発生させない。

---

## 23. Runtime Failure Classification

Operation失敗を一括して`Backend Error`にしない。

概念分類:

```text
BackendUnavailable
BackendLoadFailed
BackendCrashed
BackendTimeout
UnsupportedOperation
UnsupportedFeature
InvalidArchive
CorruptArchive
PasswordRequired
WrongPassword
AccessDenied
DiskFull
OutputCollision
SecurityPolicyViolation
ResourceLimitExceeded
Cancelled
ProtocolError
UnknownBackendError
```

Adapter固有Errorは可能な限り共通Error Modelへ変換し、元Error CodeもDiagnostic Contextとして保持する。

---

## 24. Fallback Policy

### Before Operation Start

副作用が発生していない段階では、安全に別BackendへFallback可能とする。

例:

```text
External x64 Load failed
        ↓
External x86 unavailable
        ↓
Built-in usable
        ↓
Built-inへFallback
```

通常の候補選択で発生したFallbackは、必要に応じてInfo / Debugへ記録する。

### After Operation Start

Filesystemへ変更を開始した後は無条件Fallbackしない。

```text
External Backend
↓
50 files extracted
↓
Backend failure
↓
Built-inで最初から自動再試行  ← 原則禁止
```

理由:

* File二重生成
* 上書き
* Metadata差異
* Partial output
* Archive更新時の破損

Operation PlanとOutput Stateを確認し、再試行可能な場合のみ明示的に扱う。

---

## 25. Transaction Awareness

Backend Interface自体が完全なTransactionを保証できない場合でも、ArchiveManagerはOperationの副作用状態を追跡する。

概念:

```text
NotStarted
PreflightComplete
OutputCreated
OutputModified
PartialSuccess
Completed
Failed
Cancelled
```

Fallback / Cleanup / User Notification判断に利用する。

---

## 26. Update / Delete Operations

既存Archiveを直接変更する`Update` / `Delete`はCreate / ExtractよりRiskが高い。

可能な場合は、

```text
Original Archive
      ↓
Temporary New Archive
      ↓
Validate
      ↓
Atomic / Safe Replace
```

のような方式を優先する。

ただしLegacy DLL APIがIn-place操作しか提供しない場合はCapability / Riskとして明示する。

Backendの`Update`対応をBooleanだけでなく、

```text
UpdateMode
├─ RebuildSafe
├─ InPlace
└─ Unsupported
```

のように扱うことを検討する。

詳細なFile replacement policyは別途実装設計で確定する。

---

## 27. Password / Encryption

PasswordやEncryption capabilityはFormat Supportと分離して扱う。

例:

```text
Backend A:
ZIP Extract = Yes
Encrypted ZIP Extract = No

Backend B:
ZIP Extract = Yes
Encrypted ZIP Extract = Yes
```

PasswordをLogへ出力しない。

LegacyHostへPasswordを渡す場合も、必要なOperation Scopeだけで保持し、不必要に永続化しない。

---

## 28. Unicode / Legacy Encoding Boundary

Application内部はUnicodeを基本とする。

External DLLがANSI / CP932 APIしか提供しない場合はAdapter / LegacyHost境界で変換する。

```text
Application UTF-16 / Unicode model
        ↓
Adapter Boundary
        ↓
Legacy Encoding
        ↓
External DLL
```

変換不能なFile Nameを黙って置換して処理しない。

Capability / Errorとして上位へ返し、別BackendがUnicodeを正しく扱える場合はOperation開始前にそちらを選択できるようにする。

---

## 29. Concurrency Policy

BackendごとにThread Safetyが異なるため、共通で無制限Parallel実行しない。

Backend DescriptorにConcurrency Policyを持たせる。

概念:

```text
ConcurrencyPolicy
├─ SingleGlobal
├─ SinglePerBackend
├─ SinglePerArchive
├─ MultiReadOnly
└─ FullyConcurrent
```

Legacy DLLは安全性が確認できるまで保守的なPolicyをDefaultとする。

Built-in BackendはLibrary仕様と実測に基づきPolicyを設定する。

---

## 30. Backend Discovery Cache

DLLのArchitecture、Version、Export、Capability等をOperationごとに繰り返し高コストProbeしない。

Cache Keyには少なくとも次を考慮する。

```text
Path
File Size
LastWriteTime
File Identity / Hash when needed
Adapter Version
```

次の場合はInvalidateする。

* DLL file changed
* DLL directory changed
* User requested rescan
* LhaForge / Adapter updated
* Previous Backend crash / fault

CacheはSecurity Checkを永久に省略するためのものではない。

---

## 31. Fault Quarantine

同一Session中にBackendがCrashや重大なProtocol Failureを起こした場合、即座に何度も再利用しない。

概念:

```text
Usable
  ↓ crash
Faulted
  ↓
Session quarantine
```

Userによる明示Retry、Backend再Scan、Application再起動等で解除できる構造を検討する。

特にLegacyHostで特定DLLがHostを繰り返しCrashさせる場合に有効である。

---

## 32. Backend Diagnostics

Advanced Settings / Diagnostic UIでは、Backendごとに次を確認可能にすることを検討する。

```text
Name
Backend ID
Type
Architecture
Path
Version
State
Supported Formats
Capabilities
Last probe result
Last error
```

External DLLの手動差し替え文化を維持するため、

> なぜこのDLLが使われていないのか

をユーザーが確認できることを重視する。

---

## 33. Logging

Backend選択はDebug Logで説明可能にする。

例:

```text
Operation: Create
Format: ZIP
Required: Create, ExactInputSet, UnicodeFileName

external.7zip.x64
  State: Usable
  Create: Yes
  ExactInputSet: No
  Result: Rejected

external.7zip.x86
  State: Usable
  Create: Yes
  ExactInputSet: Yes
  Result: Candidate

builtin.zip
  State: Usable
  Create: Yes
  ExactInputSet: Yes
  Result: Candidate

Selected: external.7zip.x86
Reason: highest-priority backend satisfying required capabilities
```

通常の自動選択をWarningとして大量出力しない。

Backend Crash、Security Violation、重大なCompatibility Failure等は適切な上位Levelで記録する。

---

## 34. External DLL Ownership

`dll\x64` / `dll\x86`はUser-serviceable領域である。

Installer / Updater / Repairは、

* Installer配置物
* LFCaldix等の取得物
* User手動配置物
* Unknown ownership

を区別する。

Unknown ownershipのDLLを無条件上書き・削除しない。

Backend Discoveryは「LhaForgeが配置したDLLしか使えない」設計にはしない。

ユーザーが互換DLLを手動で配置するv1系運用を正式に許容する。

---

## 35. External DLL Signature Policy

External DLLにLhaForge自身の署名を付けない。

第三者署名が存在する場合は、診断・Trust Metadataとして利用できる。

ただし、

```text
Signed = 必ず安全
Unsigned = 必ず危険
```

とは判定しない。

利用可否は、

* Location
* Architecture
* API compatibility
* Capability
* Known compatibility
* Security policy

等を総合して決定する。

将来、署名やHash Allowlist等のOptional Trust Policyを追加できる構造とする。

---

## 36. Safe Mode / Troubleshooting Mode

将来的にBuilt-in Backendのみを利用するModeを提供できる構造とする。

概念:

```text
Normal
  External x64 → External x86 → Built-in

Safe / Troubleshooting
  Built-in only
```

用途:

* External DLL障害の切り分け
* LegacyHost障害の切り分け
* 不明なExternal DLLを一時的に無効化

正式なCLI名やUIは後で決定する。

---

## 37. Backend Support Matrix

各Backend / DLL Familyについて、最終的にSupport Matrixを管理する。

最低項目:

```text
Backend Family
Tested Version
x64 Availability
x86 Availability
Formats
Operations
Unicode
Encryption
Multi-volume
ExactInputSet
Concurrency
Known Issues
Support Status
```

Status例:

```text
Supported
Supported with limitations
Experimental
Legacy
Blocked
Unknown
```

v1.6.7で対応していたという理由だけで、未検証DLLをv1.7.0で`Supported`とは記載しない。

---

## 38. Initial Priority Families

初期実装 / PoCでは、利用価値と検証容易性を考慮し、主要FamilyからBackend Abstractionを成立させる。

優先候補:

1. ZIP / 7-Zip family
2. TAR family
3. UNLHA family
4. UNRAR family
5. Built-in ZIP / TAR系
6. その他Legacy DLL Family

これは最終対応Formatを限定するものではない。

まず共通Modelが複数の異なるAPI Familyで成立することを検証する。

---

## 39. PoC Requirements

実装開始前後に最低限次を検証する。

### PoC A: External x64

* x64 DLL discovery
* Architecture validation
* Load
* Version / export probe
* Basic List / Extract

### PoC B: LegacyHost x86

* x64 → Named Pipe → x86
* DLL load
* List / Extract
* Progress
* Error
* Host crash recovery

### PoC C: ExactInputSet

* `.git` / `.env`除外
* External Backend
* Built-in Backend
* Archive内容に除外対象が入らないこと

### PoC D: Backend Fallback

* x64 incompatible
* x86 available
* Built-in available
* Expected backend selected

### PoC E: Unicode

* 日本語
* Unicode supplementary characters where supported
* Legacy conversion failure
* Backend selectionへの反映

### PoC F: Performance

* Large file count
* Large directory tree
* Discovery cache
* LegacyHost batch IPC

---

## 40. Open Items

現時点で未確定:

* 共通Backend Interfaceの具体的なC++型
* Individual DLL FamilyのAdapter仕様
* Built-in Library最終選定
* Zstd / Argon2 implementation / libsodium Version pinningとUpdate Policy
* ZSTE v1 Wire Format Freeze / Independent decoder test
* Built-in 7z Create方式
* Backend Preference UI
* Signature / Trust Advanced Policy
* Discovery Watcher方式
* Cache persistence有無
* LegacyHost Protocol wire format
* Timeout default
* Fault quarantine解除Policy
* Update / DeleteのSafe Replace方式
* Format DetectionのProbe順序
* Support Matrixの保存形式

これらはPoC、Legacy DLL調査、実装設計を通じて確定する。

---

## 41. Acceptance Criteria

Backend Architectureが実装段階へ進むための最低条件:

1. External x64 / x86 / Built-inを共通Modelで表現できる
2. Backend選択理由を説明できる
3. Required Capability不足Backendを誤選択しない
4. Filtered CreateでExactInputSetを保証できる
5. x86 DLLを64bit本体へ直接ロードしない
6. External DLL Load Pathを安全に制御できる
7. Operation開始前Fallbackと開始後Failureを区別できる
8. Backend固有Errorを共通Error Modelへ変換できる
9. DLL差し替え後にDiscovery Cacheを正しく無効化できる
10. External DLLがなくてもBuilt-in対象Formatの基本操作が可能になる設計である
11. Security ValidationがBackend Priorityより優先される
12. Performance最適化がSecurity / Correctnessを破壊しない

---

## 42. Summary

LhaForge v1.7.xのBackend Architectureは、

```text
v1系External DLL互換
       +
x64 Native Backend
       +
x86 LegacyHost
       +
Built-in Fallback
       +
Capability / Security based Selection
```

を一つのArchiveManagerで統合する。

外部DLLを残すことと現代的な安全性・可用性を両立し、Backend差異をUIやApplication Logicへ拡散させないことを基本方針とする。
