# LhaForge v1.7.0 Installer Lifecycle Design

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Development branch: `develop-v1.7.0`
- Scope: Setup / Install / Upgrade / Migration / Repair / Update / Uninstall / Recovery

Related documents:

- `architecture.md`
- `directory-layout.md`
- `ownership-matrix.md`
- `migration.md`
- `security.md`
- `performance.md`
- `signing.md`
- `logging.md`
- `encoding.md`（予定）

Related ADR:

- ADR-0001: v1.6.7を開発基準とする
- ADR-0002: v1系外部DLL互換を維持する
- ADR-0003: x64本体とLegacyHostを採用する
- ADR-0004: Built-in BackendをFallbackとして持つ
- ADR-0005: 署名可能なRelease Architectureと最小権限設計を採用する

---

## 1. Purpose

LhaForge v1.7.xのInstaller Lifecycleを、単純なFile Copy / Deleteではなく、Ownership、Migration、Repair、Recovery、Least Privilege、Securityを共有する一つのLifecycle基盤として設計する。

対象Operationは次とする。

```text
Fresh Install
Upgrade / Migration
Repair
Update
Uninstall
Recovery
```

これらは別々にFilesystemやRegistryを書き換える実装を持たず、可能な限り共通のComponent Model、Package Manifest、Install State、Transaction Engineを利用する。

主な目的:

1. 既存環境を先に破壊しない。
2. Installerが所有するものとUser / Externalが所有するものを区別する。
3. Routine Repair / UninstallをOriginal Setup.exeへ依存させない。
4. System-wide変更だけを明示的にElevationする。
5. Crash、電源断、File lock等のFailureからRecoverできる。
6. Signed / Unsigned Releaseの双方を同じLifecycleで扱える。
7. Unknown FileやUser-modified External DLLを誤削除しない。
8. 操作内容をDiagnostics可能な形でJournal / Logへ残す。

---

## 2. Design Principles

Installer Lifecycle全体で次を必須原則とする。

### 2.1 Prepare before mutate

既存状態を変更する前に、必要なPayload、Disk Space、Path、Version、Architecture、Manifest、権限、Running Process等を確認する。

```text
Inspect
↓
Plan
↓
Validate
↓
Stage
↓
Mutate
```

「まず古いFileを削除し、後から新しいFileを取得する」方式を避ける。

### 2.2 Ownership before deletion

FileがLhaForge Install Root内にあることだけを理由に削除しない。

削除・上書きの判断は、少なくとも次の情報を利用する。

- Package Manifest
- Install State
- Known Component ID
- File Version
- Hash（必要な場合）
- Ownership Classification
- User selection

### 2.3 Deletion last

Upgrade / Migrationでは旧状態からの削除をCommit直前またはCommit後へ寄せる。

Rollbackに必要な旧Fileを早期に破棄しない。

### 2.4 Least privilege

Setup UI、Update Check、Download、Plan作成等は通常権限を基本とする。

Program Files、HKLM、Machine-wide Shell Integration等を変更するOperationだけElevationする。

### 2.5 Original Setup independence

インストール後のRoutine Operationに、ユーザーがGitHub等からダウンロードした元のSetup Packageを要求しない。

最低限、次はInstalled Stateのみで成立させる。

- Uninstall
- Registration cleanup
- Install state inspection
- Recovery guidance

RepairでPayloadの再取得が必要な場合も、元Setup.exeそのものではなく、Installed Recovery Asset、Release Package、またはユーザーが指定したCompatible Packageを利用できる設計とする。

### 2.6 Signing optional, validation required

Authenticode SigningはOptionalとする。

ただし、Unsigned ReleaseであってもLifecycleがTrust無検証になることを意味しない。

Package Manifest、Hash、Expected Path、Version、Architecture等を利用する。

### 2.7 Security is not optional

署名の有無、Legacy Compatibility、Performanceを理由にPath Validation、Package Validation、Privilege Boundary等を無効化しない。

---

## 3. Lifecycle Architecture

概念Architecture:

```text
Setup.exe / Installed UI
        │
        │  User interaction / planning
        ▼
┌─────────────────────────────┐
│ Lifecycle Controller        │  Unelevated where possible
│                             │
│ - Detect                    │
│ - Inventory                 │
│ - Plan                      │
│ - Package Validation        │
│ - User Choice               │
└──────────────┬──────────────┘
               │
               │ privileged actions only
               ▼
┌─────────────────────────────┐
│ Lifecycle Core / Helper     │  Elevated only when required
│                             │
│ - Managed File mutation     │
│ - HKLM                      │
│ - Shell registration        │
│ - Machine integration       │
│ - Transaction / rollback    │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Package Manifest            │
│ Install State               │
│ Journal                     │
│ Recovery Metadata           │
└─────────────────────────────┘
```

実装時にSetup UIとLifecycle Coreを同一EXEへ含めるか別EXEへ分離するかはInstaller Framework選定時に決定する。

Architecture上は、UIとPrivileged Mutationの責務を分離できることを要求する。

---

## 4. Lifecycle Components

### 4.1 Setup Package

Public Releaseで配布するInstall入口。

概念名:

```text
LhaForge-1.7.0-Setup.exe
```

責務:

- Payload提供またはPayload取得
- Package Manifest提供
- Fresh Install開始
- Existing Install検出
- Upgrade / Migration開始
- Repair入口（対応可能な場合）
- Recovery入口

Setup Packageの最終Format / FrameworkはTBDとする。

### 4.2 Installed Lifecycle Core

Installed StateのRepair / Uninstall / Recoveryを担う内部Core。

概念配置:

```text
runtime\installer\
```

少なくともUninstallはSetup Packageなしで実行できる。

将来、次の構成のいずれかを採用できる。

```text
LifecycleCore.exe
    Install / Repair / Update / Uninstall共通
```

または

```text
InstallCore.exe
RepairCore.exe
UpdateCore.exe
UninstallCore.exe
```

v1.7.0初期設計ではComponent名より共通Lifecycle Engineを重視し、実装分割はInstaller Framework / PoC後に確定する。

### 4.3 Uninstall.exe

Rootに残すUser-facing Recovery Launcher / Stub。

```text
LhaForge\Uninstall.exe
```

完全なUninstall Engineではない。

主な責務:

- Installed Uninstall Coreの探索
- CoreのExpected Path / Identity確認
- Coreの起動
- Core欠落時のRecovery Guidance
- Setup Repairへの誘導
- Compatible Release Packageの指定入口

### 4.4 UninstallCore.exe

Target Layout上の概念配置:

```text
runtime\installer\UninstallCore.exe
```

Root StubがなくてもStandaloneで完全な通常Uninstallを実行できることを目標とする。

Windows Uninstall Registrationからは、可能な限りこのCoreへ直接到達可能にする。

### 4.5 Update Component

Update CheckとSystem Mutationを分離する。

```text
Update Check / Download
    Unelevated

Install replacement / Machine integration
    Elevation when required
```

Legacy LFCaldixを維持する場合も、新LifecycleのOwnership / Validationを迂回してManaged First-party Binaryを直接破壊的更新しないよう境界を設ける。

---

## 5. Package Model

v1.7.x Packageは、単なるFile集合ではなくComponent Metadataを持つ。

概念:

```text
Package
├─ Manifest
├─ Payload
├─ License metadata
└─ Optional signature / release metadata
```

### 5.1 Package Manifest

最低限、次の情報を表現できる形式とする。

```text
Package ID
Product ID
Product Version
Architecture
Minimum supported installer/lifecycle version
Component ID
Relative Path
File Type
File Version
Size
SHA-256
Ownership Class
Required / Optional
Install Condition
Repair Policy
Uninstall Policy
Migration Role
```

Manifest FormatはJSON等を候補とするが、最終決定は実装設計時に行う。

### 5.2 Relative path only

Package内部のFile Entryは原則Relative Pathで表現する。

Manifestから任意Absolute Path、UNC Path、Device Path等へ書き込ませない。

Install Root外への変更が必要なRegistry / Shell Integration等はFile Payloadとは別の明示Actionとして定義する。

### 5.3 Hash

Installer-managed PayloadはSHA-256等によるIntegrity確認が可能なMetadataを持つ。

Hashは次に利用する。

- Package corruption検出
- Stage validation
- Managed Fileの既知状態判定
- Repair判断
- User modification検出補助
- Recovery

Hashが一致しない既存Fileを直ちにMaliciousと決めつけない。

User modificationや別Versionの可能性を分類し、Mutation前にBackup / Policy判断する。

---

## 6. Install State

Install後はLifecycleに必要なStateをローカルに保持する。

概念情報:

```text
Product ID
Installed Version
Install Root
Install Architecture
Install ID
Installed Components
Package Manifest Version
Per-component state
Known managed hashes
Migration source version
Install / upgrade timestamp
Pending reboot state
Recovery state
```

### 6.1 Location

Installer-managed Metadataの候補:

```text
<InstallRoot>\runtime\installer\
```

Machine-wide Lifecycle Stateの候補:

```text
%ProgramData%\LhaForge\Installer\
```

一方だけに全Recovery情報を依存させない方が望ましい。

例えばInstall Rootが一部破損していても、Windows Uninstall RegistrationやMachine StateからRecovery入口へ到達できる構成を検討する。

具体PathとACLは実装時に確定する。

### 6.2 Install State is not an unquestioned trust anchor

Install State Fileが存在するだけで内容を信頼しない。

- Schema validation
- Size limit
- Path validation
- Product identity
- Version validation
- Hash / package cross-check
- Signature（存在する場合）

等を適用する。

---

## 7. Transaction Model

Lifecycle Mutationは可能な範囲でTransaction型にする。

基本Phase:

```text
Discovery
↓
Inventory
↓
Plan
↓
Preflight
↓
Stage
↓
Checkpoint
↓
Apply
↓
Validate
↓
Commit
↓
Cleanup
```

### 7.1 Stage

新しいManaged Fileを既存Fileへ直接上書きする前に、安全なStaging Areaへ展開・検証する。

Stagingでは最低限:

- File count
- Size
- Hash
- Architecture
- Expected component identity
- Path safety

を確認する。

### 7.2 Atomic replacement

Filesystem / Windows API上可能な範囲で、File replacementはAtomicまたはRollback可能なSequenceを用いる。

```text
new file staged
↓
old file backup / rename
↓
new file replace
↓
validate
```

### 7.3 Commit

新状態のValidationに成功してからCommitする。

Commit前のBackup / JournalをCleanupしない。

### 7.4 Cleanup

Commit後もCrash RecoveryやDiagnosticsに必要なJournalを一定範囲保持できる。

不要になったPayload / Staging / BackupのみPolicyに従ってCleanupする。

---

## 8. Journal

Mutation OperationはJournalを持つ。

最低限:

```text
Operation ID
Operation Type
Source Version
Target Version
Install Root
Start Time
Current Phase
Action Sequence
Completed Actions
Rollback Data
Commit State
Pending Reboot State
Last Error
```

SecretやCredentialは記録しない。

JournalはCrash後に「途中だったから無条件で続きを実行する」ためだけのものではない。

再起動時には現在のFilesystem / Registry状態を再検証し、次を判断する。

```text
Resume
Rollback
Repair
Manual recovery required
```

---

## 9. Fresh Install

Fresh Installの基本Flow:

```text
Launch Setup
↓
Package Validation
↓
Choose / validate install path
↓
Select optional components
↓
Create Install Plan
↓
Preflight
↓
Elevation if required
↓
Stage
↓
Install Managed Files
↓
Create Install State
↓
Register Integration
↓
Validate
↓
Commit
↓
Cleanup
```

### 9.1 Default path

64bit新規Installの既定:

```text
%ProgramFiles%\LhaForge\
```

Custom Install Pathを許容する方向とする。

### 9.2 Existing non-LhaForge directory

選択Pathに既存Fileが存在する場合、Directoryを丸ごとInstaller所有とみなさない。

Known LhaForge Installationでない既存DirectoryへのInstallは、警告、Subdirectory提案、またはCollision Validationを行う。

### 9.3 Fresh install and legacy assets

Fresh Installでは`dll\` / `cldx\`を空で作成するか、Bundled / licensed Componentだけ配置するかをPackage Policyで決定する。

Third-party external DLLを無条件同梱しない。

---

## 10. Upgrade and Migration

v1.6.x → v1.7.0は`migration.md`を使用するSpecial Migrationとする。

```text
Existing legacy install
↓
Migration Engine
↓
v1.7.0 Install State
```

v1.7.x → later v1.7.xでは、可能な範囲で通常Update / Upgrade Modelへ移行する。

### 10.1 In-place first

Legacy Install Pathを検出した場合、既定ではIn-place Upgradeを優先する。

Custom Pathや`Program Files (x86)`にあるという理由だけで自動的に別Rootへ移動しない。

### 10.2 User-serviceable data

次はManaged First-party Payloadと同じReplace Policyを適用しない。

```text
dll\x64\
dll\x86\
cldx\
User configuration
Shared legacy configuration
Unknown files
```

### 10.3 Layout migration

Legacy RootにあるFirst-party Componentを`runtime\`へ再配置する場合、旧Binaryを削除する前に新配置での動作 / RegistrationをValidationする。

---

## 11. Repair

Repairは「Install Folderを初期状態へ戻す」機能ではない。

Repairの目的:

- 欠落したManaged Fileの復元
- 破損したManaged Fileの復元
- Installer-managed Registrationの修復
- Install Stateの整合性修復
- 必要に応じたMigration Recovery

### 11.1 Repair categories

Repair Planでは少なくとも次を区別する。

```text
Missing managed component
Corrupt managed component
Unexpected version
User-modified managed component
External/user-serviceable component
Unknown file
Configuration issue
Registration issue
```

### 11.2 User-modified managed file

Managed Path上のFileでもKnown Hashと異なる場合、無条件で元に戻さない。

可能なら:

- Backup
- Difference classification
- User confirmation
- Restore

を行う。

Security-critical Coreが不正状態でRepair自体を安全に実行できない場合は、Trusted / validated Setup PackageからのRecoveryを優先する。

### 11.3 External DLL

Repairは次を原則変更しない。

```text
dll\x64\
dll\x86\
```

ただしInstaller自身が明示的にBundledしてOwnershipを保持するComponentが存在する場合のみ、そのComponent単位のPolicyをManifestで定義する。

### 11.4 cldx

Repairで`cldx`を初期化・削除しない。

### 11.5 Repair source

Repair PayloadのSource候補:

1. Installed Recovery Asset
2. Local Package Cache（採用する場合）
3. Matching Release Package
4. User-selected compatible Setup Package

Original Setup.exeの保存を必須にしない。

---

## 12. Update

Updateは次のPhaseへ分ける。

```text
Check
↓
Metadata Validation
↓
Download
↓
Package Validation
↓
Create Update Plan
↓
Stage
↓
Apply
↓
Validate
↓
Commit
```

### 12.1 Check / download without elevation

Update CheckやDownloadのためだけにUACを表示しない。

### 12.2 Update metadata

Release Metadataには少なくとも次を持てる設計とする。

```text
Product / Channel
Version
Architecture
Package URL or identity
Package size
SHA-256
Minimum updater version
Migration requirement
Optional signature metadata
```

具体的な配信Format、GitHub Releases API使用有無、Update ChannelはTBD。

### 12.3 Download before mutation

Downloadが完了し、Package Validationが成功するまで既存Installを変更しない。

### 12.4 Signed and unsigned

Unsigned Release:

```text
Release metadata
+ Hash
+ Package structure validation
```

Signed Release:

上記にAuthenticode / Publisher / Timestamp等を追加可能とする。

### 12.5 Downgrade

自動UpdateでVersion Downgradeを通常Operationとして許可しない。

Rollback / Manual installとして実施する場合は、Config Schema、Migration State、Backend Compatibilityを考慮した明示Operationとする。

---

## 13. Running Processes and File Locks

Install / Update / Repair / Uninstallでは、対象Binaryの使用中状態を確認する。

対象例:

- `LhaForge.exe`
- `MenuEditor.exe`
- `Unregister.exe`
- LegacyHost
- LFCaldix
- Shell Extension DLL
- Installer Core

### 13.1 Graceful close first

可能なComponentには通常終了を要求する。

User Data損失につながる強制終了を既定にしない。

### 13.2 Shell Extension

Explorer等がShell Extension DLLをLoadしているため置換・削除できない場合がある。

選択肢:

- Registrationを先に無効化
- Explorer restartを案内 / 選択可能にする
- Reboot後置換 / 削除

どの方式を採るかはShell PoC後に確定する。

### 13.3 Reboot

再起動要求を「失敗」と同一視しない。

Install State / JournalにPending Rebootを明示し、再起動後にValidation / Cleanupできるようにする。

不要なRebootは要求しない。

---

## 14. Privilege Separation

### 14.1 Unelevated operations

原則通常権限:

- Setup UI表示
- License / Release Note表示
- Install Detection
- Inventory（権限範囲内）
- Plan作成
- Package Download
- Hash Validation
- User-level Configuration
- Update Check

### 14.2 Elevated operations

必要な場合だけ昇格:

- `%ProgramFiles%`への書き込み / 削除
- HKLM変更
- Machine-wide Shell Integration
- Machine-wide Association
- Protected LocationのMigration

### 14.3 No implicit arbitrary elevation

Elevated Coreは、Unelevated Processから渡された任意Path / Commandをそのまま管理者権限で実行しない。

IPC / command line inputはSchema / Operation / PathをValidateし、許可されたLifecycle Actionだけを実行する。

External BackendやUnknown EXEをElevated Coreから実行しない。

---

## 15. Uninstall Architecture

通常Uninstallの目的は、LhaForge v1.7.xが管理するApplication ComponentとSystem Integrationを安全に解除することであり、Install Root配下の全Fileを無条件に消すことではない。

基本Flow:

```text
Launch UninstallCore
↓
Read / validate install state
↓
Inventory current state
↓
Create removal plan
↓
Show retained-data summary
↓
Quiesce running components
↓
Remove system integration
↓
Remove managed files
↓
Validate
↓
Commit uninstall state
↓
Self-clean / reboot cleanup if required
```

### 15.1 Default uninstall policy

既定で削除するもの:

- First-party Managed Binary
- `runtime\`内のInstaller-managed Component
- Installer-managed Resource
- Installer-managed License copies
- LhaForgeが作成したMachine-wide Registration
- LhaForge専用Uninstall Registration
- 安全に特定できるDisposable Cache / Temp

既定で保持するもの:

- User configuration
- User-created / user-modified external archive DLL
- `cldx`
- User Log
- Unknown File
- Ownershipを確定できないFile

### 15.2 Optional cleanup

Uninstall UIでは追加Cleanupを明示的に選択できる設計とする。

候補:

```text
[ ] ユーザー設定を削除
[ ] ログ・キャッシュを削除
[ ] 外部アーカイバDLLを削除
[ ] cldxのLegacy Assetを削除
```

既定はOFFとする。

「完全削除」という一つの曖昧なOptionだけでUnknown Fileまで削除しない。

### 15.3 Unknown files

Install RootにUnknown Fileが残る場合、Directory自体を削除しない。

例えば:

```text
C:\Program Files\LhaForge\custom-notes.txt
```

があれば、Managed Component削除後にRoot Folderが残ってもData Preservationを優先する。

### 15.4 External DLL cleanup

External DLL削除をユーザーが明示選択した場合でも、対象を列挙してOwnership / Pathを確認する。

Installer自身が取得したKnown External BackendとUser手動配置物を可能な範囲で区別する。

Third-party DLLを「LhaForge.exeと同じFolderにあるから」という理由だけで削除しない。

### 15.5 cldx cleanup

`cldx`削除は独立した明示Optionとする。

Legacy Documentation、Source、License等を含む可能性があるため、Cache Cleanupと同一視しない。

### 15.6 Self deletion

`UninstallCore.exe`自身を実行中に削除できない場合、次の候補を使用する。

- 小型Self-clean Helper
- Reboot後Delete
- OSが許すDelayed cleanup

Self-clean方式はInstaller Framework選定後に確定する。

Cleanup Helperを採用する場合も、任意Path削除Utilityにしない。

---

## 16. Windows Uninstall Registration

WindowsのInstalled Apps / Programs and Features相当から到達できるUninstall Registrationを作成する。

少なくとも次を適切に設定する方向とする。

```text
DisplayName
DisplayVersion
Publisher / project identity
InstallLocation
UninstallString
DisplayIcon
```

具体Registry View、Value、Version policyはImplementation設計で確定する。

### 16.1 UninstallString

可能ならInstalled `UninstallCore.exe`へ直接到達する。

```text
<InstallRoot>\runtime\installer\UninstallCore.exe
```

Root `Uninstall.exe`だけをSingle Point of Failureにしない。

### 16.2 Publisher

Authenticode Publisherの有無とInstalled Apps上のPublisher表示は概念上分離する。

Public Signingを採用しないReleaseでもProduct metadataとしてProject / Distributor表記を持てる。

最終表記はRelease Policyで決定する。

---

## 17. File Association and Shell Integration

Association / Shell IntegrationはInstaller LifecycleでOwnershipを追跡する。

### 17.1 Preserve previous state

v1系互換として、変更前のAssociation情報を復元可能な範囲で保持する。

Legacy `LhaForgeOrgFileType`等の既存挙動はBaseline / Migration調査と合わせて扱う。

### 17.2 Uninstall

LhaForgeが登録したAssociationを解除する際、他Applicationが後から設定したAssociationを上書きして旧状態へ強制復元しない。

Current StateがLhaForge所有状態か確認した上で解除・復元する。

### 17.3 Unregister.exe

`Unregister.exe`はv1系User-facing Artifactとして残す。

v1.7.xでは、旧`LFAssist*.exe`と`epuninst.exe`へそのまま委譲する必要はない。

新LifecycleのRegistration Cleanup API / Coreを利用できる構造とする。

`Unregister.exe`実行がApplication本体のUninstallを暗黙実行するかどうかはLegacy Behavior確認後に最終確定する。

---

## 18. Recovery

Recoveryは通常Repairとは別に考える。

想定Failure:

- `Uninstall.exe`欠落
- `UninstallCore.exe`欠落 / 破損
- Install State破損
- Migration途中
- Pending Reboot途中
- Managed Binary一部欠落
- Shell Registrationだけ残存
- Setup途中でCrash

### 18.1 Recovery paths

優先順の概念:

```text
Installed Core usable
    ↓
Installed Recovery metadata usable
    ↓
Matching Setup / Release Package
    ↓
User-selected compatible package
    ↓
Manual cleanup guidance
```

### 18.2 Exact version requirement

Recoveryに必ず「元と完全一致するSetup.exe」が必要とはしない。

ただしVersion跨ぎRecoveryではMigration Compatibilityを確認する。

Current v1.7.x Setupが旧InstallをRepair / Upgradeできる場合は利用できる。

互換性がない場合は適切なRelease Packageが必要であることを明示する。

### 18.3 Recovery must not guess destructive actions

Install Stateが壊れてOwnershipを判断できない場合、Folder丸ごと削除等の推測的Cleanupを行わない。

まずInventoryとKnown Component Detectionを実施し、確度の高いActionだけを提案する。

---

## 19. Recovery Assets and Package Cache

Routine UninstallのためにFull Setup Packageを永久保存することは必須としない。

一方、Repair / Recoveryに必要な最小Assetは保持できる構造にする。

### 19.1 Candidate assets

```text
Install State
Package Manifest
Known component hashes
Rollback / migration metadata
Small recovery launcher/core
Release identity
```

### 19.2 Full package cache

Full Payload Cacheを採用する場合は、Disk UsageとのTrade-offを明示する。

候補Policy:

```text
No full cache
Keep current-version repair payload
Keep last successful update rollback payload temporarily
```

最終Policyは実装時のPackage Size / Built-in Backend dependency等を見て決定する。

---

## 20. Rollback

Rollback可能性をLifecycle Operationの設計条件とする。

### 20.1 Before commit

Commit前のFailureは原則旧状態へ戻す。

### 20.2 After commit

Commit後の問題は通常Repair / explicit rollbackとして扱う。

### 20.3 User data

RollbackでUser Dataを過去状態へ無条件巻き戻さない。

Config Migrationで変更した場合はMigration-specific Backup / reversible transformationを利用する。

### 20.4 External DLL

User-serviceable External DLLをRollback対象のManaged Binaryと同じ扱いにしない。

Installer自身が変更したことをJournalで確認できる対象だけ戻す。

---

## 21. Reboot and Deferred Actions

File lock等で即時変更できない場合、Deferred Actionを利用できる。

状態例:

```text
PendingFileReplace
PendingFileDelete
PendingShellCleanup
PendingValidation
```

再起動後は状態を再検証する。

Deferred Actionが完了したと仮定してJournalだけ進めない。

---

## 22. Security Requirements

Installer Lifecycleは高権限Operationを持つため、Application本体以上にInputをUntrustedとして扱う。

### 22.1 Path safety

- Canonicalized path validation
- Install Root escape防止
- Traversal防止
- UNC / Device path policy
- Reparse Point / Symlink考慮
- Trailing dot / space考慮
- ADS考慮
- Root / drive deletion防止

### 22.2 Manifest safety

- Schema validation
- Size / count limit
- Duplicate path検出
- Case-insensitive collision検出
- Architecture validation
- Hash validation
- Unknown action拒否

### 22.3 Elevated core boundary

- Allow-listed operation
- Request schema validation
- Expected caller / session validation where practical
- Arbitrary command execution禁止
- Arbitrary DLL loading禁止
- Arbitrary recursive delete禁止

### 22.4 TOCTOU

Validation後Mutation前に対象が差し替えられる可能性を考慮する。

特にTemp / Staging / Privilege Boundary周辺ではDirectory ACL、Handle-based operation等をPoCする。

### 22.5 Logging

Credential、Secret、Private key、`.env`内容等をLogへ出さない。

Path / File NameにもSensitive情報が含まれ得る。

---

## 23. Performance Requirements

Installerの安全性のために全Fileを何度もFull Hashするなど、無制限な重処理は避ける。

### 23.1 Inventory reuse

同一Operation内で取得したFilesystem InventoryをPlan / Validation / UIへ再利用する。

### 23.2 Hash policy

HashがSecurity / Ownership判断に必要なManaged FileはHashする。

巨大なUser-owned / Unknown Fileを無条件Full Hashしない。

### 23.3 Staging

同一Volume内で安全にAtomic replaceできる場合等、不要なData Copyを減らす。

ただしPerformanceのためRollbackabilityやIntegrity Checkを捨てない。

### 23.4 UI responsiveness

Long-running Inventory、Hash、Download、Stage処理でUI ThreadをBlockしない。

Progress更新頻度を制御し、大量FileでUI overheadがOperation本体を支配しないようにする。

---

## 24. Logging and Diagnostics

Lifecycle OperationではComponent単位で診断可能にする。

記録候補:

```text
Operation ID
Operation Type
Version from / to
Install Root
Phase
Component ID
Action
Result
Rollback result
Reboot required
Error category
```

Event IDは共通Logging設計のInstaller / Updater領域`3000`番台を利用する方向とする。

詳細Severity / Sink / Retentionは`logging.md`で定義する。

---

## 25. Silent / Automated Operation

将来的な管理用途を考慮し、UI専用Architectureにしない。

候補Operation:

```text
install
repair
update
uninstall
registration-cleanup
```

ただしSilent ModeでもSecurity確認、Package Validation、Ownership Policyを省略しない。

Destructive Optionを暗黙Defaultにしない。

Command-line switchの最終仕様はInstaller Framework確定後に設計する。

---

## 26. Installation Scope

v1.7.0初期はInstaller版を対象とし、Portable EditionをScope外とする。

Machine-wide Installを基本案とするが、将来Per-user Installを検討できるよう、Application Coreを「Program Filesに必ず存在する」という前提へ過度に結合しない。

ただしv1.7.0でPer-user Installを提供することは約束しない。

---

## 27. Component Ownership Summary

| Category | Install | Repair | Update | Uninstall default |
|---|---|---|---|---|
| First-party managed binaries | Install | Restore/validate | Replace | Remove |
| `runtime\` managed assets | Install | Restore/validate | Replace | Remove |
| `resources\` | Install | Restore | Replace | Remove |
| `licenses\` copies | Install | Restore | Replace | Remove |
| `dll\x64\` / `dll\x86\` | Preserve / explicit provision | Preserve | Preserve unless explicitly managed | Preserve |
| `cldx\` | Preserve / create as needed | Preserve | Preserve | Preserve |
| User config | Create/migrate | Preserve | Migrate only when required | Preserve |
| Logs | Generated | Preserve | Preserve | Preserve |
| Cache | Generated | Recreateable | Recreateable | Cleanup possible |
| Unknown files | Preserve | Preserve | Preserve | Preserve |
| System integration owned by LhaForge | Register | Repair | Update | Remove safely |

明示Cleanup Optionを選択した場合だけ、User config / logs / external DLL / `cldx`の追加削除を実施できる。

---

## 28. Interaction with Legacy Components

### 28.1 epuninst.exe

v1.6.7の`epuninst.exe`はLegacy Installer / Uninstaller由来のComponentとしてBaselineを保持する。

v1.7.xでは新Lifecycleへ置換し、通常Runtime dependencyにはしない方向とする。

Migration時には旧Uninstall Registration / Stateを安全に解除するため必要な範囲だけ利用・認識する。

### 28.2 LFAssist / LFAssist64

Legacy Association / Shell操作の責務を調査済みComponentとして扱う。

新ArchitectureではMachine-wide Mutationを新Lifecycle / Registration Layerへ移す方向とする。

互換性のため残す場合も、任意高権限Helperとして利用し続けない。

### 28.3 LFCaldix

External DLL更新文化を維持するCompatibility Componentとして扱う。

Managed First-party LifecycleとはOwnershipを分離し、LFCaldixが取得するExternal BackendをInstallerのManaged Payloadとみなさない。

---

## 29. Test Strategy

Installer Lifecycleは実装後、Disposable VM Snapshotを用いて検証する。

最低限のScenario:

### Fresh Install

- Clean Windows
- Default Path
- Custom Path
- Existing non-empty Directory
- Unsigned Build
- Signed Test Build（署名機構PoC時）

### Upgrade / Migration

- Clean v1.6.7
- v1.6.7 first run済み
- External DLL download済み
- Custom DLL配置済み
- `cldx`あり
- Custom Install Path
- Missing legacy component
- Modified managed binary

### Repair

- Managed EXE欠落
- Runtime DLL欠落
- Hash mismatch
- External DLL差し替え
- Install State一部破損

### Uninstall

- Default uninstall
- User configあり
- External DLLあり
- `cldx`あり
- Unknown Fileあり
- Running LhaForge
- ExplorerがShell Extension load中
- Pending reboot

### Failure Injection

- Stage中Crash
- Apply中Crash
- Registry mutation後Crash
- Disk full
- Access denied
- Locked file
- Corrupt package
- Hash mismatch
- Power-loss相当の中断

各Scenarioで「成功したか」だけでなく、Data Lossがないこと、Rollback / Recoveryが成立すること、残存Stateが説明可能であることを確認する。

---

## 30. Installer Framework Requirements

具体的なInstaller Frameworkは未決定とする。

選定時に最低限評価する条件:

1. x64 Application対応
2. Custom Actionを安全に制御できる
3. Least Privilege設計との相性
4. Repair / Upgrade / Uninstall
5. Transaction / Rollbackまたは独自Engineとの統合性
6. Shell Extension登録
7. Custom Install Path
8. Reboot / locked file対応
9. Silent operation
10. Signed / Unsigned双方
11. CI/CDとの統合
12. OSSとしてのLicense / redistribution条件
13. 長期Maintenance性
14. Windowsの将来Versionへの追従性

Installer Framework固有機能へOwnership / Migration Logicを過度に閉じ込めない。

---

## 31. Open Items

実装開始前または関連PoCで確定する項目:

- Installer Framework
- Setup Package形式
- Lifecycle CoreのEXE分割
- Package ManifestのSchema / Encoding
- Install Stateの具体Format
- `%ProgramData%`内の具体Path / ACL
- Recovery Asset retention
- Full Package Cacheを持つか
- Update Distribution方式
- Update Channel
- Shell Extensionのlocked-file / Explorer restart policy
- Reboot deferred action方式
- Uninstall Core self-delete方式
- Windows Uninstall Registrationの最終Value
- Silent mode CLI
- Per-user Installを将来許容するか
- Legacy `Unregister.exe`の最終挙動
- LFCaldixとのUpdate責務境界

これらを未確定のままにしても、Ownership、Transaction、Least Privilege、Data Preservation、RecoveryというArchitecture Principleは変更しない。

---

## 32. Architecture Principle

LhaForge v1.7.xのInstallerは、

> 「LhaForge Folderにあるものを入れ替えるSetup」

ではなく、

> 「各ComponentのOwnershipと現在状態を理解し、必要な変更だけを安全に適用し、失敗しても復旧できるLifecycle Manager」

として設計する。

特に、External Archive DLLや`cldx`を維持するLhaForge v1系では、InstallerがInstall Root全体を所有しているという前提を置かないことを重要なCompatibility / Safety要件とする。
