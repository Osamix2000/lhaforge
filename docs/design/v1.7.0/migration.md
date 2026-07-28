# LhaForge v1.7.0 Migration Design

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Primary scenario: LhaForge v1.6.7からv1.7.0への安全なUpgrade / Migration
- Integration branch: `main-osamix`
- Development branch: `develop-v1.7.0`

Related documents:

- `architecture.md`
- `ownership-matrix.md`
- `directory-layout.md`
- `backend.md`
- `security.md`
- `performance.md`
- `signing.md`
- `installer.md`
- `logging.md`（予定）

---

## 1. Purpose

LhaForge v1.7.0では、v1.6.7以前の既存環境を単純なFile Overwriteで更新しない。

旧環境には、Installerが配置したBinaryだけでなく、次のような状態が共存し得る。

- `LhaForge.ini`等のユーザー設定
- `LFCaldix.ini`等のShared Compatibility設定
- LFCaldixが取得したExternal Archive DLL
- ユーザーが手動で交換したDLL
- `cldx`内の説明書、License、SDK、Source Package等
- File Association
- Shell Extension Registration
- Custom Install Path
- 旧Installer / Uninstallerの状態
- ユーザーがInstall Directoryへ独自に置いた未知File

そのためv1.7.0へのUpgradeは、既存状態を観測・分類・保全した上で新Architectureへ移行する**Migration**として扱う。

最優先事項は次の通りとする。

1. 既存環境を先に破壊しない。
2. User-owned / External-owned Dataを無条件に上書きしない。
3. 変更前にRecovery可能な情報を残す。
4. 新状態を検証してからCommitする。
5. Failure時は可能な限り旧状態へ戻す。
6. Unknownなものは原則Preserveする。
7. Migration結果を後から説明できるようJournal / Logを残す。

---

## 2. Scope

本Documentで主に扱うのは次のMigrationである。

```text
LhaForge v1.6.7
        ↓
LhaForge v1.7.0
```

将来のv1.7.x間Upgradeでも同じTransaction / Ownership原則を再利用できるようにするが、v1.6.x → v1.7.0はDirectory Layout、x64化、Backend Architecture、Installer Lifecycleが変わるため特別なMajor Migrationとして扱う。

### 2.1 In scope

- Install Directory検出
- Legacy Version識別
- Existing File Inventory
- Ownership分類
- Configuration Migration
- External Backend Migration
- `cldx` Preservation
- Registry / Association Migration
- Shell Integration Migration
- Installer / Uninstaller Lifecycle移行
- Backup / Rollback
- Recovery metadata
- Migration Log / Journal
- Custom Install Path
- 部分的に壊れた旧環境

### 2.2 Out of scope

- ユーザーのArchive File自体の変換
- Archive内部Contentsの書き換え
- Third-party External DLLの自動修復保証
- Portable Editionへの変換
- 他のArchiver Applicationからの設定Import

---

## 3. Migration Modes

Migration Engineは少なくとも次のModeを区別する。

### 3.1 Fresh Install

旧LhaForge環境が検出されない場合。

```text
FreshInstall
```

Migration処理は原則不要だが、同じInstaller Lifecycle / Validation / Journal Infrastructureを利用できるようにする。

既定Install Path:

```text
%ProgramFiles%\LhaForge\
```

### 3.2 In-place Upgrade

既存v1.6.7環境を同じInstall Rootでv1.7.0へ移行する。

v1.7.0ではこれを既定Migration方式とする。

例:

```text
C:\Program Files (x86)\LhaForge\
        ↓
同じRootを維持してv1.7.0へMigration
```

または:

```text
D:\Tools\LhaForge\
        ↓
D:\Tools\LhaForge\
```

64bit Applicationであることだけを理由に、既存の`Program Files (x86)`やCustom Pathから自動的に別Directoryへ強制移動しない。

理由:

- Shortcut / Association / Script等の既存Path依存を減らす
- User-managed DLL / `cldx`との位置関係を維持する
- Migrationの変更範囲を小さくする
- Rollbackを単純化する

### 3.3 Explicit Relocation

ユーザーが明示的に新Pathへの移動を選択した場合のみ、Relocation Migrationを許容する。

例:

```text
C:\Program Files (x86)\LhaForge\
        ↓
C:\Program Files\LhaForge\
```

RelocationはIn-placeより変更範囲が大きいため、v1.7.0初期実装ではPoC結果によって提供可否を決定する。

提供する場合も、通常Upgradeの既定にはしない。

### 3.4 Repair / Recovery Migration

旧環境または移行途中の環境が部分的に壊れている場合。

例:

- `epuninst.exe`欠落
- Shell Extensionのみ登録が残っている
- Main EXEのみ欠落
- `LFCaldix.ini`は存在するがLFCaldix本体がない
- Migration途中のJournalが残っている

この場合は「通常Upgrade」と同一視せず、観測された状態から安全なRecovery Planを作成する。

---

## 4. High-level Transaction

基本Flowは次とする。

```text
Detect
  ↓
Inspect
  ↓
Inventory
  ↓
Classify Ownership
  ↓
Create Migration Plan
  ↓
Preflight Validation
  ↓
Backup / Snapshot
  ↓
Stage New Payload
  ↓
Quiesce / Unregister Legacy Integration
  ↓
Apply Migration
  ↓
Validate New State
  ↓
Register New Integration
  ↓
Commit
  ↓
Post-validation
  ↓
Cleanup
```

Failure時:

```text
Failure
  ↓
Stop further mutation
  ↓
Journal state確認
  ↓
Rollback可能?
  ├─ Yes → Rollback → Validate old state
  └─ No  → Recovery state保持 → Repair案内
```

CleanupはCommitおよびPost-validationより前に行わない。

---

## 5. Detection

Migration開始時に既存LhaForge Installation Candidateを探索する。

候補Source:

- Windows Uninstall Registration
- LhaForge固有Registry情報
- Running executable / selected executable path
- Known default installation locations
- UserによるManual Folder selection

特定のRegistry Key名はLegacy Baseline調査とInstaller実装時に確定する。

単に`LhaForge.exe`というFileが存在するだけでInstallationと判定しない。

### 5.1 Candidate validation

Candidateは複数Evidenceを組み合わせてValidationする。

例:

- `LhaForge.exe`存在
- File Version / Product metadata
- Known Companion Binary
- `LFCaldix.exe`
- `MenuEditor.exe`
- `Unregister.exe`
- Shell / Association state
- Config pathとの整合

Legacy環境が不完全でもMigration Candidateになり得るため、「既知Fileが1つ欠ける = Reject」とはしない。

代わりにConfidenceを持つ。

```text
Confirmed
High
Medium
Ambiguous
Invalid
```

### 5.2 Manual selection

自動検出できない場合はユーザーがLegacy Install Folderを指定できる。

指定FolderはValidationし、無関係なDirectoryへMigration処理を適用しない。

Ambiguousな場合は自動処理を続行せず、理由を表示する。

---

## 6. Inventory

Migration対象Directoryを変更する前にInventoryを作成する。

最低限記録する項目:

```text
Relative Path
File / Directory
Size
Last Write Time
File Version（取得可能な場合）
PE Architecture（PEの場合）
Hash（必要な対象）
Known Component ID
Ownership Classification
Planned Action
```

Registryについても変更対象Key / ValueのSnapshotを作る。

### 6.1 Hash policy

すべての巨大Fileを無条件でHashしてMigration開始を遅くしない。

Hashは主に次へ利用する。

- First-party Managed Binaryの既知版判定
- User modification検出
- Backup verification
- Staged payload verification
- Recovery対象のIntegrity確認

Size / timestamp / metadataで十分なDiscovery Cacheと、Security / Mutation判断に必要なHashを区別する。

---

## 7. Ownership Classification

Inventory後、各ObjectをOwnership Matrixに基づいて分類する。

基本Category:

```text
Managed
User Configuration
Shared Compatibility Configuration
User-serviceable External Backend
Legacy Managed Asset
Unknown / User-preserved
Legacy Installer State
Generated / Temporary
```

### 7.1 Managed

例:

- `LhaForge.exe`
- `MenuEditor.exe`
- `Unregister.exe`
- `LFAssist.exe`
- `LFAssist64.exe`
- `ShellExtDLL*.dll`
- `LFCaldix.exe`
- `b2e32.dll`（Legacy Baseline上のBundled Component）

既知のv1.6.7 Managed Binaryであることが確認できる場合はv1.7.0 Managed Componentへ置換・移行できる。

ただし既知Hash / Versionと一致しない場合はUser modificationの可能性を考慮し、Backup後に扱う。

### 7.2 User Configuration

例:

```text
LhaForge.ini
```

原則Preserveし、v1.7.0 Schemaへ必要な項目だけMigrationする。

旧Fileそのものを即時破棄しない。

### 7.3 Shared Compatibility Configuration

例:

```text
LFCaldix.ini
```

LhaForge / LFCaldix双方が扱うLegacy StateとしてPreserveする。

Known settingはMigrationできるが、未知Keyを安易に削除しない。

### 7.4 User-serviceable External Backend

例:

```text
7-ZIP32.DLL
TAR32.DLL
UNLHA系DLL
その他External Archive DLL
```

旧Root等から検出した場合、次を調査する。

- PE Architecture
- File Version
- Known Backend type
- API compatibility
- User modification可能性

v1.7.xのTarget Layoutへ移す場合は、Architectureに応じて原則次へ分類する。

```text
x64 → dll\x64\
x86 → dll\x86\
```

ただし自動移動前にBackend Compatibilityを確認し、Unknown DLLを無理にLoad対象へ昇格させない。

旧Locationの削除はMigration Commit後まで行わない。

### 7.5 Legacy Managed Asset

```text
cldx\
```

原則Preserveする。

In-place UpgradeでRootが維持される場合、不要な移動をしない。

内容をCacheとして削除・再生成しない。

### 7.6 Unknown / User-preserved

Install Directory内に存在するがOwnershipを判定できないFile / Directory。

原則:

```text
Do not delete
Do not overwrite
Do not reinterpret as managed data
```

Migration Logへ記録する。

新LayoutとPath conflictする場合は自動上書きせず、Conflictとして扱う。

---

## 8. Migration Plan

Inventoryを直接Mutation処理へつなげず、一度Migration Planを生成する。

Plan Entry例:

```text
Source
Destination
Ownership
Action
Backup Required
Validation
Conflict Policy
Rollback Action
Reason
```

Action例:

```text
Preserve
Copy
Move
Replace
Transform
Register
Unregister
RemoveAfterCommit
Ignore
Conflict
```

Planを確定してからMutationを開始する。

これにより、処理途中で「次に何をするか」を場当たり的に決めない。

---

## 9. Preflight Validation

Mutation前に少なくとも次を確認する。

### 9.1 Environment

- Install Path accessibility
- 必要Disk space
- Backup / Stage領域の作成可否
- 対象Volume
- File lock状況
- OS / Architecture requirements
- Installer package integrity

### 9.2 Running processes

変更対象Binaryを使用中のProcessがある場合は検出する。

例:

- `LhaForge.exe`
- `MenuEditor.exe`
- `LFCaldix.exe`
- LFAssistant
- LegacyHost（将来Upgrade時）

ユーザーデータを失う可能性がある強制終了を安易に行わない。

### 9.3 Shell Extension

Explorer等がLegacy Shell DLLをLoadしている可能性を考慮する。

Registration解除とFile replacementは別問題として扱う。

DLLが使用中の場合の再起動要求 / delayed replacement等は`installer.md`で定義する。

### 9.4 Conflict

Target Layoutと同名のUnknown / User-owned Fileが存在する場合、上書きしない。

例:

```text
runtime\legacy\LhaForgeLegacyHost.exe
```

に未知Fileが既に存在する場合は、自動削除せずConflictとして停止または別Recovery処理を要求する。

---

## 10. Backup and Snapshot

Migration前に「元へ戻すために必要なもの」を保存する。

BackupはInstall Directory全体を毎回無条件複製することを意味しない。

MutationするObjectを中心に差分Backupする。

### 10.1 Backup target

- Replace / Move / Delete予定のLegacy Managed File
- 変更するConfiguration
- Registry Value / Key
- Association state
- Shell registration state
- Installer / Uninstaller registration
- Migration metadata

`cldx`や巨大なUnknown File等、変更しないものは原則その場でPreserveし、無駄なCopyを避ける。

### 10.2 Backup metadata

BackupにはManifestを持たせる。

例:

```text
Migration ID
Source version
Target version
Timestamp
Original install root
Files
Hashes
Registry snapshot
Planned actions
Applied actions
Commit state
```

### 10.3 Backup location

Backup / Recovery Dataは`Program Files`内の通常Runtime領域と混在させない。

具体的なMachine Data Pathは`installer.md`で確定する。

Recoveryに必要な最小情報はUninstall / Repair Infrastructureから到達可能にする。

---

## 11. Staging

新しいv1.7.0 Payloadを旧Fileへ直接上書きしながら展開しない。

先にStage領域へ展開し、次をValidationする。

- Package Manifest
- Expected File set
- Size / Hash
- PE Architecture
- Version metadata
- Signature（存在する場合）
- Required runtime dependencies

Signed / Unsigned Release双方を許容するため、Authenticode署名の存在自体を必須条件にしない。

ただし署名が存在する場合はAdditional Validationへ利用する。

可能な範囲でFinal destinationと同一Volume上にStageを作り、Atomic rename / replaceを利用しやすくする。

---

## 12. Elevation Boundary

Migration全体を最初から管理者権限で実行することを必須としない。

通常権限で可能な処理:

- Detection
- Inventory
- Plan生成
- Download
- Package validation
- User config inspection

Machine-wide変更が必要になった時点でElevated Coreへ明示的に移行する。

例:

```text
Plan / Validation
    normal privilege
        ↓
Mutation of Program Files / HKLM / machine-wide shell integration
        ↓
Explicit elevation
```

Elevated側は事前に作られたPlanを再Validationし、Callerから渡された任意Path / Commandを無条件に実行しない。

---

## 13. Legacy Integration Quiesce

旧Binaryを置換する前に、必要なIntegrationを安全に解除・停止する。

対象候補:

- Shell Extension registration
- File Association
- Legacy Assistant registration
- Update helper

v1.6.7の`Unregister.exe` / `LFAssist*` / `epuninst.exe`の責務はLegacy Evidenceとして利用するが、v1.7.0 Migrationで旧Uninstallerをそのまま全面的に実行することを前提にしない。

理由:

旧Uninstallerへ処理を委譲すると、v1.7.0がPreserveすべきUser Data / External DLLまで旧Deletion Policyで処理される可能性があるためである。

必要な登録解除はv1.7.0側がOwnership-awareに制御する。

---

## 14. File Migration

### 14.1 First-party managed binaries

Known Legacy Managed BinaryはBackup後にv1.7.0版へ置換する。

Target Layoutが変わるComponentは、Compatibility確認後に新Locationへ配置する。

例:

```text
Legacy root\LFAssist.exe
        ↓
runtime\assistant\LFAssist.exe
```

ただし実際のPath依存が確認されたComponentについては`directory-layout.md`を優先し、PoC完了前に強制移動しない。

### 14.2 Root cleanup

旧Rootに存在するManaged Fileを新Locationへ移した場合も、旧File削除は新State Validation / Commit後に行う。

Unknown Fileを「古そうだから」という理由で削除しない。

### 14.3 External DLL

External DLLはFirst-party Binaryと同じReplace処理を行わない。

Architecture別DirectoryへMigrationする場合は、元FileをPreserveできるRecovery手段を確保する。

同名DLLがTargetに存在する場合は、Versionが新しいという理由だけで上書きしない。

Ownership / User modification / Compatibilityを評価する。

---

## 15. Configuration Migration

設定Migrationは「旧INIを新INIで全面置換」ではなく、Schema-awareに行う。

### 15.1 LhaForge.ini

原則:

- Existing configをPreserve
- Known settingを読み取る
- v1.7.x Setting modelへMapping
- Unknown settingは可能な限り保持
- Migration不能値はDefaultへ黙って置換せず診断する

旧ConfigのEncodingもLegacy Dataとして認識する。

### 15.2 LFCaldix.ini

Shared Compatibility Configurationとして扱う。

LhaForge / LFCaldix双方が利用してきたStateを考慮し、Known keyだけを一方的に再生成しない。

DLL install path等のLegacy Path情報はExternal Backend Migration時のEvidenceとして利用する。

### 15.3 New settings

v1.7.0で追加される設定例:

- Archive Input Exclusion Policy
- Custom Exclusion Rules
- Archive-name extraction directory policy
- Backend policy
- Logging

Legacy configに存在しないため、明示的なDefault値を定義する。

Migrationによって過去に存在しないSecurity-sensitive機能を勝手に有効化しない。

---

## 16. External Backend Migration

旧v1.xのExternal Archive DLLはBackend Discovery対象としてMigration Inventoryへ取り込む。

### 16.1 Classification

```text
PE x64
    → x64 candidate

PE x86
    → x86 / LegacyHost candidate

Unknown / invalid
    → preserve, but do not load
```

### 16.2 Probe

Fileを新Layoutへ認識させる前にBackend Probeを行う。

- Architecture
- Loadability
- Exports
- API version
- Adapter compatibility
- Capability

Unsafe / incompatibleなDLLをMigrationしたという理由だけでEnabledにしない。

### 16.3 User choice

将来的にMigration UIを設ける場合、検出Backendについて次を表示できるようにする。

```text
DLL
Architecture
Version
Compatibility
Migration action
Reason
```

ただし通常ユーザーへ不要な低レベル選択を強制しない。

安全なDefault Planを生成し、Advanced optionとして詳細を確認できる形を目標とする。

---

## 17. cldx Migration

`cldx`はLegacy Assetとして原則そのままPreserveする。

In-place UpgradeではPathを変更しない。

```text
<InstallRoot>\cldx\
```

を継続する。

内容のVersionが古い、Source Packageが不要に見える等の理由で自動Cleanupしない。

将来的にユーザーが明示的なCleanupを要求する場合は、Migrationとは別機能として設計する。

---

## 18. Registry and Association Migration

RegistryはOwnershipとScopeを考慮する。

分類例:

```text
Application registration
Uninstall registration
File association
Shell extension
Application settings
Legacy helper state
```

Mutation前にRelevant ValueをSnapshotする。

### 18.1 Association preservation

ユーザーがLhaForgeへ関連付けていたExtensionを可能な範囲で維持する。

ただし旧v1.xが関連付け前のFileTypeを退避している場合、その復元情報を破壊しない。

既存の第三者Application associationをLhaForgeへ勝手に変更しない。

### 18.2 Shell registration

旧Shell Extensionを解除した後、新Shell ComponentのValidationが成功してから新RegistrationをCommitする。

Registration失敗時は、可能であれば旧状態へRollbackするか、明示的なRecovery Stateとして記録する。

---

## 19. Installer / Uninstaller Transition

v1.6.7の旧Installer lifecycleからv1.7.x lifecycleへ移行する。

旧環境では`epuninst.exe`等が存在する可能性がある。

v1.7.xでは概念上次を採用する。

```text
Uninstall.exe
    Recovery Launcher / User-facing Stub

runtime\installer\UninstallCore.exe
    Standalone uninstall core
```

Migration後はWindows Uninstall Registrationをv1.7.x側へ切り替える。

旧Uninstaller Binaryは、Rollback可能期間中に必要なLegacy Evidence / Recovery Assetとして扱う場合がある。

Commit前に削除しない。

最終的なRetention期間・Cleanupは`installer.md`で定義する。

---

## 20. Validation Before Commit

Migration適用後、Commit前に新環境をValidationする。

最低限の候補:

- Main EXE expected architecture / version
- Required first-party files
- Directory layout consistency
- Config readability
- Backend discovery service initialization
- LegacyHost startup / protocol handshake（必要な場合）
- Registry consistency
- Association registration consistency
- Shell component file integrity
- Uninstall / Repair metadata

可能であればApplication full launch前にMachine-readable validationを行う。

「File copyが成功した」だけでMigration成功としない。

---

## 21. Commit Point

Commitは明確なTransaction stateとして記録する。

```text
Prepared
Applying
Applied
Validated
Committed
CleanupComplete
```

`Committed`になるまではRollback用Legacy Assetを削除しない。

Commit後に新StateがOfficial stateとなる。

Migration JournalはCommit後もDiagnostics / Repairに必要な範囲で保持する。

---

## 22. Cleanup

Cleanupは最後に行う。

対象候補:

- 旧Managed BinaryのBackup copy
- Stage directory
- Temporary migration file
- Superseded registration metadata

削除してよいことがOwnership上明確なものだけを対象とする。

以下はCleanup対象として自動推定しない。

- `cldx`
- External DLL
- Unknown File
- User config
- User-created backup

Cleanup中のFailureはMigration本体の成功を直ちに無効化しない。

`Committed but cleanup incomplete`として記録できるようにする。

---

## 23. Rollback

Rollbackは「新Fileを消して旧Fileを戻す」だけではなく、変更したStateを逆順に復元する。

例:

```text
New shell registration解除
↓
Registry復元
↓
Config復元
↓
New managed files退避/削除
↓
Legacy managed files復元
↓
Legacy integration再登録
↓
Validation
```

各Migration Actionは可能な限りCorresponding Rollback Actionを持つ。

### 23.1 Rollback limit

外部環境の変化等により完全Rollbackが不可能な場合がある。

例:

- Migration中にユーザーがFileを変更
- Explorer / Security softwareがFileをLock
- External DLLの更新を同時に実施
- Disk error

この場合は「Rollback成功」と偽らず、Partial Recovery Stateとして残す。

---

## 24. Crash and Power-loss Recovery

Migration Engine自体がCrashまたはOS再起動しても、次回起動時に状態を判断できるようJournalをDurableに保存する。

重要なMutation前後でTransaction stateをFlushする。

例:

```text
Migration ID: ...
State: Applying
Last completed action: 42
Next action: 43
Commit: false
```

再開時はCurrent filesystem / registry stateを再検証し、単純にAction 43から無条件再開しない。

Stateに応じて、

- Resume
- Rollback
- Repair

の安全な経路を選択する。

---

## 25. Migration Journal and Logging

Migrationは監査可能な記録を残す。

最低限:

```text
Migration ID
Source version
Target version
Source path
Target path
Start / end time
Privilege boundary
Detected components
Ownership classification
Conflicts
Backups
Actions
Validation results
Warnings / errors
Commit state
Rollback state
```

Sensitive DataをLogへ不用意に残さない。

例:

- Password
- Environment secret value
- Archive contentsの機密Data

Path自体にも機密情報が含まれる可能性を考慮し、Diagnostic detail levelとの関係は`logging.md`で定義する。

---

## 26. Security Requirements

Migrationは高権限でFilesystem / Registryを変更するため、通常Runtime以上に入力を信頼しない。

必須原則:

- Canonical path validation
- Install root boundary validation
- Reparse point / symlink handling
- Path traversal prevention
- Arbitrary command execution禁止
- Package manifest validation
- Hash validation
- Signature validation（存在する場合）
- Elevated Core側でPlan再検証
- Temporary directory ACL
- Secure replacement
- TOCTOU低減

旧Install Directory内に攻撃者が配置した未知EXE/DLLを「LhaForgeの一部らしい」という理由でElevated実行しない。

Legacy Helperを利用する場合もPath / Identity / Expected behaviorをValidationする。

---

## 27. Performance Requirements

安全性を保った上でMigration時間とI/Oを抑える。

- 変更しない巨大Assetを無意味にCopyしない
- `cldx`全体Backupを必須にしない
- File Hashは必要性に応じて実施
- Inventory traversalを可能な限り共有
- Stage / final directoryが同一VolumeならAtomic operationを活用
- Registry snapshotをRelevant scopeへ限定
- ProgressをUIへ過剰頻度で通知しない

Performance最適化のためにBackup / Validation / Rollback capabilityを削除しない。

---

## 28. User Experience

通常ユーザーには可能な限り安全なDefault Planを提示する。

例:

```text
LhaForge v1.6.7が検出されました。
既存の設定・外部DLL・cldxを保持してv1.7.0へ更新します。
```

詳細表示では、例えば次を確認可能にする。

```text
既存Install Path
検出Version
保持する設定
検出External DLL数
Unknown / preserved item
Migration warning
Backup / rollback availability
```

ConflictやSafety issueがない限り、一般ユーザーへ個々のFile actionを大量に選択させない。

一方、External DLLを手動保守しているAdvanced Userには、Preserve判断を確認できるDiagnostic情報を提供する。

---

## 29. Example Scenarios

### 29.1 Standard v1.6.7

```text
v1.6.7 default installation
+ default configuration
+ LFCaldix used
+ external DLLs
+ cldx
```

Expected:

- Existing rootを検出
- User config preserve
- LFCaldix config preserve / migrate
- External DLLをInventory / classify
- `cldx` preserve
- Managed binaryをv1.7.0へ更新
- New lifecycle registrationへ切替

### 29.2 Custom installation path

```text
D:\Tools\LhaForge\
```

Expected:

- Pathを勝手に`Program Files`へ移さない
- In-place migrationをDefaultとする
- Registry / associationを現在Pathに合わせて更新

### 29.3 User-replaced 7-ZIP32.DLL

Expected:

- First-party Managed Fileとして上書きしない
- x86 External BackendとしてInventory
- Compatibility probe
- `dll\x86`へのMigration candidate
- OriginalをRollback可能に保持

### 29.4 Unknown files in installation root

```text
LhaForge\my-notes.txt
LhaForge\custom-tool.exe
```

Expected:

- Preserve
- 自動削除しない
- Elevated実行しない
- Conflictしない限りMigration継続

### 29.5 Missing legacy uninstaller

```text
epuninst.exe missing
```

Expected:

- Migration自体を即座に不可能としない
- Existing stateをInventory
- v1.7.x Lifecycleへ直接移行可能か評価
- Legacy uninstallerをInternetから適当な版で補完しない

### 29.6 Interrupted migration

Expected:

- JournalからUncommitted migrationを検出
- Current state再Validation
- Resume / Rollback / Repairの安全なActionを選択

---

## 30. Future v1.7.x Upgrade

v1.7.0以降は可能な限り通常のManaged Upgradeへ簡素化する。

ただしOwnership原則は維持する。

```text
Managed
    Installer / Updaterが更新可能

User Configuration
    Preserve / Schema migration

User-serviceable Backend
    無条件上書き禁止

Legacy Asset
    Lifecycle policyに従う
```

v1.7.xのDirectory LayoutやConfig Schemaへ破壊的変更が必要になった場合は、新しいMigration Versionを明示する。

---

## 31. Open Items

実装前に確定が必要な項目:

- Legacy Registry Key / Uninstall Registrationの完全Inventory
- LhaForge.iniの最終保存先とSchema
- LFCaldix.iniの最終Compatibility policy
- Migration backup / journalのMachine Data Path
- Backup retention期間
- Explicit Relocationをv1.7.0で提供するか
- Shell DLL lock時の再起動 / delayed replacement policy
- Installer Framework
- Recovery package format
- Config migration engineの形式
- External Backendの旧Locationから新`dll`への具体的移行手順
- B2E / lficons / Legacy Helperの最終配置

これらはLegacy PoC、`installer.md`、`logging.md`、`encoding.md`の設計と合わせて確定する。

---

## 32. Core Principle

v1.6.7 → v1.7.0 Migrationでは、

> 新しい状態を作るために古い状態を先に壊さない。

ことを最重要原則とする。

```text
Observe
  ↓
Classify
  ↓
Plan
  ↓
Preserve
  ↓
Stage
  ↓
Apply
  ↓
Validate
  ↓
Commit
  ↓
Cleanup
```

の順序を維持し、未知・ユーザー所有・外部所有のDataをInstaller都合で破壊しない。

Migrationの安全性は、v1.7.xにおけるCompatibility、Recoverability、Securityの一部として扱う。
