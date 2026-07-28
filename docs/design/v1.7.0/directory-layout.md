# LhaForge v1.7.0 Directory Layout

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Scope: Installer版の実行時配置、書き込み可能データ領域、Legacy資産、Repair / Migration / Uninstall時の扱い

Related documents:

- `architecture.md`
- `ownership-matrix.md`
- `archive-operations.md`
- `security.md`
- `performance.md`
- `signing.md`
- `backend.md`
- `migration.md`
- `installer.md`

---

## 1. Purpose

LhaForge v1.7.xでは、v1.6.7の分かりやすい構成とユーザーが直接保守できる外部DLL文化を残しながら、Application本体、内部Runtime、External Backend、Legacy Asset、ユーザー設定、Log、Temp、Installer Recovery資産を明確に分離する。

Directory Layoutでは次を重視する。

1. ユーザーが直接利用するものは見つけやすくする。
2. 内部HelperやRuntime ComponentをRootへ無秩序に並べない。
3. External Archive DLLはユーザーが確認・交換できる独立領域とする。
4. `cldx`は単純なCacheとして扱わずLegacy Assetとして維持する。
5. `Program Files`配下へ通常のユーザー設定、Log、Tempを書き込まない。
6. Machine-wide変更が必要な場合だけElevationする。
7. Repair / UpdateがUser-ownedまたはExternal-owned Dataを無条件に上書きしない。
8. Security、Recoverability、Migrationの境界をPathからも判断できるようにする。

Portable Editionはv1.7.0初期目標に含めない。

---

## 2. Directory Domains

v1.7.xでは、Pathを大きく次のDomainへ分ける。

```text
Installation Domain
    Program binaries / managed runtime / external backends / legacy assets

User Data Domain
    Per-user configuration and persistent user state

Machine Data Domain
    Shared compatibility state / installer lifecycle state when required

Temporary Domain
    Per-operation temporary files and working directories
```

Applicationは「LhaForgeのファイルだから」という理由だけでInstallation Directoryへ書き込まない。

各DataのOwnershipとLifecycleを基に保存先を決定する。

---

## 3. Default Installation Root

新規64bitインストールの既定Pathは次を基本案とする。

```text
%ProgramFiles%\LhaForge\
```

例:

```text
C:\Program Files\LhaForge\
```

v1.6.7からのUpgradeでは、既存Install Pathを検出してMigration Policyに従う。

旧環境が例えば次の場合も、単純に新規既定Pathへ強制移動しない。

```text
C:\Program Files (x86)\LhaForge\
D:\Tools\LhaForge\
その他のCustom Path
```

最終的なIn-place Migration / Path relocation policyは`migration.md`で定義する。

---

## 4. Target Installation Layout

概念上の最終配置は次を基本とする。

```text
LhaForge\
├─ LhaForge.exe
├─ MenuEditor.exe
├─ Unregister.exe
├─ Uninstall.exe
│
├─ dll\
│  ├─ x64\
│  └─ x86\
│
├─ cldx\
│
├─ runtime\
│  ├─ legacy\
│  │  ├─ LhaForgeLegacyHost.exe
│  │  └─ ...
│  │
│  ├─ shell\
│  │  ├─ x64\
│  │  │  └─ ShellExtDLL64.dll
│  │  └─ x86\
│  │     └─ ShellExtDLL.dll
│  │
│  ├─ assistant\
│  │  ├─ LFAssist.exe
│  │  └─ LFAssist64.exe
│  │
│  ├─ installer\
│  │  ├─ UninstallCore.exe
│  │  ├─ package-manifest.*
│  │  └─ recovery\
│  │
│  └─ update\
│     ├─ LFCaldix.exe
│     └─ ...
│
├─ resources\
│  ├─ icons\
│  ├─ help\
│  └─ ...
│
└─ licenses\
```

これはArchitecture上のTarget Layoutであり、Legacy Componentの技術制約によって特定Fileを例外配置する必要が判明した場合は、PoC結果を記録した上で本Documentを更新する。

---

## 5. Installation Root Policy

Root Directoryは、ユーザーが直接認識・起動するFirst-party Componentを中心に置く。

### 5.1 LhaForge.exe

```text
LhaForge\LhaForge.exe
```

主Application。

- First-party Managed Binary
- x64を基本とする
- 通常は`asInvoker`
- Repair / Update対象
- Uninstall対象
- Signed / Unsigned双方のReleaseを許容

Rootから移動しない。

### 5.2 MenuEditor.exe

```text
LhaForge\MenuEditor.exe
```

v1系でユーザーが認識してきたMenu編集ComponentとしてRootに維持する。

内部実装が将来変更されても、User-facing Artifactとしての存在を可能な限り維持する。

### 5.3 Unregister.exe

```text
LhaForge\Unregister.exe
```

v1系の登録解除操作を継承するUser-facing / Legacy-facing ComponentとしてRootに維持する。

v1.7.xでは旧`LFAssist`等への単純委譲をそのまま維持するとは限らないが、ユーザーから見た入口は残す。

### 5.4 Uninstall.exe

```text
LhaForge\Uninstall.exe
```

小型のUser-facing Recovery Launcher / Stubとする。

責務:

- Uninstall入口
- `UninstallCore.exe`の探索・検証・起動
- Core欠落・破損時のRecovery案内
- 必要に応じたRepairへの誘導

完全なUninstall LogicをRoot Stubへ複製しない。

WindowsのUninstall Registrationは、可能であればStandaloneな`UninstallCore.exe`へ直接到達可能な構成とする。

---

## 6. External Backend Directory

External Archive DLLは次に分離する。

```text
dll\
├─ x64\
└─ x86\
```

### 6.1 Purpose

このDirectoryは内部Runtimeを隠す場所ではない。

v1系の特徴である、ユーザーによるExternal Backendの確認・更新・差し替えを正式に許容するUser-serviceable領域とする。

### 6.2 Architecture separation

```text
dll\x64\
    LhaForge.exe x64から直接利用可能なExternal Backend

dll\x86\
    LhaForgeLegacyHost.exe x86を介して利用するExternal Backend
```

Architecture判定はDirectory名だけを信用せず、PE Header等から実Architectureを検証する。

誤ったArchitectureのDLLが配置されている場合は読み込まず、診断可能なLogを残す。

### 6.3 Ownership

External DLLは原則として次のいずれかのOwnershipを持つ。

- LFCaldix / Backend Managerによる取得物
- Userによる手動配置物
- Migrationによって旧環境から継承されたもの

Installer-managed Binaryとは区別する。

Repair / Upgradeでは無条件上書きしない。

### 6.4 Program Files and elevation

Default Installが`%ProgramFiles%`の場合、DLLの追加・交換にはWindowsのAccess Control上Elevationが必要になる場合がある。

その場合でもLhaForge本体を常時管理者実行にはしない。

```text
User requests backend update
        ↓
Download / validation under normal privilege where possible
        ↓
System modification required
        ↓
Explicit elevation
        ↓
Atomic replace / validation
```

とする。

---

## 7. cldx Directory

```text
LhaForge\cldx\
```

`cldx`はLegacy LFCaldixが取得したDLLに付属する説明書、資料、SDK、License、Source Package等を保存してきたLegacy Asset Directoryである。

Runtime DLL Directoryとは分離する。

```text
dll\
    実際にBackendとしてLoadするExternal DLL

cldx\
    LFCaldix由来の説明書・資料・Package Asset
```

### 7.1 Lifecycle

- Migration時は原則Preserve
- Repair時は原則Preserve
- Update時に無条件削除しない
- Uninstall時は既定Preserveとし、明示Cleanup Option選択時のみ削除対象にできる
- Temporary Cacheとして扱わない

### 7.2 Compatibility

既存LFCaldixとの互換性のためRoot直下の`cldx`名称を維持する。

将来内部Backend Managerを追加しても、このLegacy Asset領域を自動的に別用途へ転用しない。

---

## 8. runtime Directory

```text
LhaForge\runtime\
```

ユーザーが通常直接起動・編集する必要のないFirst-party Runtime / Helperを配置する。

`runtime`は原則Installer-managed領域である。

ユーザーが手動で差し替えるExternal Archive DLLは置かない。

---

## 9. runtime\legacy

```text
runtime\legacy\
```

Legacy Compatibilityのための内部Componentを置く。

### 9.1 LhaForgeLegacyHost.exe

```text
runtime\legacy\LhaForgeLegacyHost.exe
```

- x86 Process
- x86 External Archive DLL Bridge
- User-facing Applicationではない
- First-party Managed Binary
- LhaForge本体から制御
- 原則`asInvoker`
- DLLを利用するためだけに管理者権限を要求しない

必要なFile Access権限は、通常のArchive Operationと同じUser Contextを基本とする。

### 9.2 Other legacy runtime

B2E等のBundled Legacy Componentについて、現代化後もFirst-party distribution assetとして必要な場合はこの領域への配置を候補とする。

例:

```text
runtime\legacy\b2e\
```

ただしLegacy APIが特定Pathを要求する場合はCompatibility PoC後に最終配置を確定する。

`b2e32.dll`をUser-serviceable External DLLと同一Ownershipにはしない。

---

## 10. runtime\shell

Shell Integration Componentを格納する。

```text
runtime\shell\
├─ x64\
│  └─ ShellExtDLL64.dll
└─ x86\
   └─ ShellExtDLL.dll
```

### 10.1 x64

64bit Explorerを主対象とするShell Extension。

Windows x64をv1.7.xの主要Targetとするため、x64 Shell ExtensionをPrimaryとする。

### 10.2 x86

32bit Shell ClientとのCompatibilityが必要な場合にのみ維持する。

最終的なSupport範囲はShell Integration設計およびPoCで決定する。

### 10.3 Registration

COM / Shell Registrationは絶対Pathで行う。

Componentが`runtime\shell`へ存在することを前提にRegistration Pathを構築し、Current DirectoryやDLL Search Pathへ依存しない。

登録・解除でMachine-wide変更が必要な場合だけElevationする。

---

## 11. runtime\assistant

```text
runtime\assistant\
```

旧v1.xで使用されてきた登録操作補助ComponentのCompatibility領域。

候補:

```text
LFAssist.exe
LFAssist64.exe
```

v1.7.x最終ArchitectureでLFAssistの機能を新しい共通Registration Layerへ置き換えられる場合、これらを永久に残すことは要求しない。

そのため、この領域は次のいずれかになり得る。

- Active compatibility helper
- Migration helper
- Legacy-only component
- 不要となり配布対象外

最終判断はShell / Installer / Migration設計後に行う。

Rootへ戻さない。

---

## 12. runtime\installer

```text
runtime\installer\
```

Installer Lifecycleに必要な内部Managed ComponentとMetadataを保存する。

概念例:

```text
runtime\installer\
├─ UninstallCore.exe
├─ package-manifest.*
├─ install-state.*
└─ recovery\
   └─ ...
```

### 12.1 UninstallCore.exe

完全なUninstall処理を単独実行できるCoreとする。

```text
runtime\installer\UninstallCore.exe
```

- First-party Managed Binary
- 必要なMachine-wide削除時のみElevation
- Root `Uninstall.exe`が欠落しても直接実行可能
- Original Setup.exeをRoutine Uninstallに要求しない

### 12.2 Installer metadata

Uninstall / Repairに必要なFile Ownership、Version、Hash、Component state等を保存する。

Security-sensitive metadataについては、単なるFile存在だけをTrust判断に使用しない。

Metadataの役割とIntegrity Policyは`installer.md`で定義する。具体Format / Schemaは実装設計時に確定する。

### 12.3 Recovery assets

必要最小限のRecovery Assetを保持できる構造とする。

ただし、巨大なFull Setup Cacheを無条件に永久保存することは要求しない。

Disk UsageとRecoverabilityを両立するPolicyをInstaller設計で決定する。

---

## 13. runtime\update

```text
runtime\update\
```

更新関連の内部Componentを置く。

Legacy互換としてLFCaldixを維持する場合のTarget例:

```text
runtime\update\LFCaldix.exe
```

LFCaldixをRootへ置かないことでRoot clutterを減らすが、Applicationの設定画面等から従来同様に利用可能とする。

Legacy LFCaldixが自分自身の配置場所に依存する処理を持つ場合はCompatibility AdapterまたはPath設定によって吸収する。

どうしてもRoot配置が必要と判明した場合のみ例外をDocument化する。

将来新しいUpdater / Backend Managerを導入する場合も同領域を使用できる。

---

## 14. resources Directory

```text
resources\
```

Applicationが配布するRead-only Resourceを置く。

候補:

```text
resources\
├─ icons\
│  └─ lficons.dll
├─ help\
│  ├─ LhaForgeHelp.chm
│  └─ ReadMe.txt
└─ ...
```

### 14.1 Policy

- Installer-managed
- Repairで復元可能
- User configurationを保存しない
- Log / Temp / Cacheを保存しない

Legacy CodeがResourceをRoot相対Pathで参照する場合、Build Modernization時にApplication Directory基準の明示Pathへ移行する。

Compatibility上Root配置が不可避なResourceだけ例外とする。

---

## 15. licenses Directory

```text
licenses\
```

LhaForge本体およびBundled Third-party ComponentのLicense / Noticeを保存する。

例:

```text
licenses\
├─ LhaForge.txt
├─ third-party-notices.txt
└─ <component>\
   └─ ...
```

External Backendを別途取得する場合、そのLicense文書を`cldx`等の取得Asset側に保持する場合がある。

Installerが第三者ComponentをBundledする場合は、そのDistribution Licenseに従い`licenses`へ必要文書を含める。

---

## 16. Per-user Data Domain

通常ユーザーが変更する永続DataはInstallation Directoryへ保存しない。

基本候補:

```text
%APPDATA%\LhaForge\
```

および

```text
%LOCALAPPDATA%\LhaForge\
```

用途によってRoaming / Localを分ける。

### 16.1 Roaming data

ユーザー設定など、Machine固有でない永続Dataの候補:

```text
%APPDATA%\LhaForge\
├─ LhaForge.ini
└─ ...
```

v1.6.7では設定Pathに複数のLegacy Ruleが存在するため、v1.7.xの最終Config LocationとMigration precedenceは`encoding.md` / `migration.md` / Configuration設計で確定する。

Legacy `LhaForge.ini`を発見した場合、勝手に破棄せずMigration対象として扱う。

### 16.2 Local data

Machine固有または大量になり得るDataの候補:

```text
%LOCALAPPDATA%\LhaForge\
├─ Logs\
├─ Cache\
└─ Temp\
```

Roaming Profileへ大きなLogやCacheを流さない。

---

## 17. Machine-wide Data Domain

Machine共有状態が必要な場合は次を使用する。

```text
%ProgramData%\LhaForge\
```

Legacy Compatibility上、v1.6.7では`LFCaldix.ini`がCommon AppData側に存在する場合がある。

候補:

```text
%ProgramData%\LhaForge\
├─ LFCaldix.ini
└─ ...
```

`LFCaldix.ini`はLFCaldixだけのPrivate Cacheではなく、LhaForge本体も参照・更新してきたShared Compatibility Configである。

そのためMigrationでOwnershipを一方へ決め打ちしない。

新しいMachine-wide metadataを追加する場合も、User settingsと混在させない。

---

## 18. Logging Layout

LogはInstallation Rootへ保存しない。

File Logの既定候補:

```text
%LOCALAPPDATA%\LhaForge\Logs\
```

Runtime Logの概念例:

```text
%LOCALAPPDATA%\LhaForge\Logs\
├─ LhaForge.log
├─ LegacyHost.log
└─ Shell.log
```

Machine-wide Installer / Migration等のLifecycle LogはOwnershipとACLが異なるため、必要に応じて`%ProgramData%\LhaForge\Logs\Lifecycle\`等のMachine Data Domainへ分離する。最終PathはInstaller PoCで確定する。

Rotation、Retention、Component分割、Sensitive Data、LogとLifecycle Journalの分離Policyは`logging.md`で定義する。

Windows Event Logを有効にする場合はFile Pathとは独立したSinkとして扱う。

Sensitive DataをLogへ出さない方針は`security.md`に従う。

---

## 19. Temporary Layout

Archive Operationの作業DataはWindowsのUser Temp領域を基本とする。

概念例:

```text
%TEMP%\LhaForge\<operation-id>\
```

またはApplication管理Local Temp:

```text
%LOCALAPPDATA%\LhaForge\Temp\<operation-id>\
```

最終PathはSecurity / Performance評価後に決定する。

### 19.1 Requirements

- Operationごとに衝突しないDirectory
- 推測困難なIdentifierまたは安全なOS APIによる作成
- Junction / Reparse等を考慮したValidation
- Cleanup失敗を診断可能にする
- Crash後の古いTempを安全に回収可能にする
- Archive内容全体を無条件にTempへCopyしない

v1.6.7の`%AppData%\LhaForge\temp\` fallbackはLegacy Baselineとして記録するが、そのまま新規Architectureの既定にはしない。

---

## 20. Compression Exclusion Configuration

圧縮時の除外RuleはApplication Configurationであり、ArchiveやInstallation Rootへ埋め込まない。

概念上、次のUser Configurationに含める。

```text
%APPDATA%\LhaForge\
```

設定項目例:

```text
CompressionExclusionMode
CompressionExclusionRules
```

Ruleには少なくとも次を表現可能とする。

- Pattern
- Enabled
- File / Directory / Both
- Root only / Any depth
- Description

初期候補:

```text
.git
.svn
.hg
.env
.env.*
```

`.gitignore`等を自動的に除外対象へ含めるとは限らない。

Rule Formatの詳細はConfiguration / `archive-operations.md`で定義する。

---

## 21. Archive Destination Policy and Paths

「Archive名を使用して展開先Folderを作成する」機能はDirectory Layoutそのものを固定する機能ではなく、Operation PlannerがDestination Pathを生成するPolicyとして扱う。

例:

```text
D:\Downloads\source.tar.gz

Extract root:
D:\Work\

Policy:
Archive name directory

Result:
D:\Work\source\
```

同じ場所へ展開するModeでは:

```text
D:\Downloads\source.tar.gz
        ↓
D:\Downloads\source\
```

Destination生成後は`security.md`のPath Validationを適用する。

Archive内EntryがDestination Rootの外へ出ることを許可しない。

---

## 22. Old v1.6.7 to v1.7.x Placement Mapping

旧Clean Installで確認した主なComponentのTarget Mapping案:

| v1.6.7 | v1.7.x Target | Classification | Notes |
|---|---|---|---|
| `LhaForge.exe` | `LhaForge.exe` | Managed / User-facing | Root維持 |
| `MenuEditor.exe` | `MenuEditor.exe` | Managed / User-facing | Root維持 |
| `Unregister.exe` | `Unregister.exe` | Managed / Legacy-facing | Root維持 |
| `epuninst.exe` | Active componentとしては移行しない | Legacy migration input | 新Uninstallerへ置換 |
| `LFAssist.exe` | `runtime\assistant\LFAssist.exe`（必要時） | Managed / Compatibility | 最終要否TBD |
| `LFAssist64.exe` | `runtime\assistant\LFAssist64.exe`（必要時） | Managed / Compatibility | 最終要否TBD |
| `LFCaldix.exe` | `runtime\update\LFCaldix.exe` | Managed / Legacy compatibility | Root依存有無をPoC |
| `ShellExtDLL.dll` | `runtime\shell\x86\ShellExtDLL.dll`（必要時） | Managed | x86 Shell compatibility |
| `ShellExtDLL64.dll` | `runtime\shell\x64\ShellExtDLL64.dll` | Managed | x64 primary |
| `lficons.dll` | `resources\icons\lficons.dll`候補 | Managed Resource | Legacy path依存をPoC |
| `b2e32.dll` | `runtime\legacy\b2e\`候補 | Managed Legacy Component | Exact path TBD |
| `b2e32.txt` | `resources`または`licenses`等 | Managed Documentation | 内容/Licenseにより分類 |
| `LhaForgeHelp.chm` | `resources\help\LhaForgeHelp.chm` | Managed Resource | Applicationから明示Path |
| `ReadMe.txt` | `resources\help\ReadMe.txt`候補 | Managed Documentation | Repository READMEとは別 |
| External Archive DLL | `dll\x86\` / `dll\x64\` | User-serviceable Backend | Architecture検証して分類 |
| `cldx\` | `cldx\` | Legacy managed assets | Root名称維持 |
| `LhaForge.ini` | User configuration domain | User configuration | Migration policy TBD |
| `LFCaldix.ini` | Machine/shared compatibility domain | Shared compatibility config | Legacy locationを尊重 |

この表はMigration設計とPoC結果に応じて更新する。

---

## 23. Repair Policy by Directory

| Path | Default Repair Policy |
|---|---|
| Root First-party EXE | ManifestとVersionを確認し復元/更新可能 |
| `runtime\` | Installer-managedとして復元/更新可能 |
| `resources\` | Installer-managedとして復元可能 |
| `licenses\` | Installer-managedとして復元可能 |
| `dll\x64\` | 原則Preserve、無条件上書き禁止 |
| `dll\x86\` | 原則Preserve、無条件上書き禁止 |
| `cldx\` | Preserve |
| `%APPDATA%\LhaForge` | User DataとしてPreserve |
| `%LOCALAPPDATA%\LhaForge\Logs` | Repair対象外 |
| `%LOCALAPPDATA%\LhaForge\Cache` | 必要に応じ再生成可 |
| `%ProgramData%\LhaForge` | Ownershipを確認して処理 |

「存在しないManaged Fileを復元する」と「User-modified Fileを元に戻す」を同じRepair処理として扱わない。

---

## 24. Uninstall Policy by Directory

Uninstallの詳細は`installer.md`で定義する。Directory Layout上の原則は次とする。

### Managed binaries

通常Uninstallで削除対象。

```text
Root managed EXE
runtime\
resources\
licenses\
```

### External/User-serviceable data

無条件削除しないPolicyを検討する。

```text
dll\
cldx\
User configuration
```

ユーザーが追加・交換したExternal DLLをInstaller所有物として一括削除するとData Lossにつながるため、Install Manifest / Ownership判定を利用する。

### Generated disposable data

Cache / Tempは安全に削除可能な範囲でCleanupする。

Logの削除Policyはユーザー選択またはInstaller Policyとして別途決定する。

---

## 25. Security Boundaries

Directoryの意味をSecurity Boundaryの一部として使用する。

```text
Managed executable code
    Root / runtime

User-serviceable executable backend
    dll

Legacy downloaded assets
    cldx

User configuration
    AppData

Machine shared state
    ProgramData

Ephemeral data
    Temp / Cache
```

ただし「正しいDirectoryに存在する」だけではTrustしない。

実行コードについては必要に応じて次を確認する。

- Expected Path
- File Type
- Architecture
- Manifest / Package metadata
- Hash
- Version
- Authenticode signature（存在する場合）

Signed / UnsignedどちらのReleaseでもPath Validation、Ownership Validation、Least Privilegeを維持する。

---

## 26. Performance Considerations

Directory Layoutを理由に不要なFile CopyやScanを増やさない。

特に:

- Archive Inputを`runtime`やTempへ全Copyしてから処理しない
- `dll` DiscoveryをOperationごとにDirectory全Scanし続けない
- Capability Cacheを安全に利用する
- `cldx`の大量DocumentationをBackend Discovery対象にしない
- Log / CacheをRoaming AppDataへ大量保存しない

Security Validationを省略することで性能を稼がない。

---

## 27. Repository Layout Is Separate

このDocumentが定義する主対象はInstalled ProductのDirectory Layoutである。

Source Repositoryを直ちに次のInstalled Layoutへ合わせて大規模移動することはしない。

現時点のv1.6.7 Source Treeを維持し、Build ModernizationおよびComponent統合時にSource Repository側のLayoutを別途決定する。

つまり:

```text
Repository layout
    !=
Installed product layout
```

である。

Directory設計を理由に、実装開始前の段階で既存C++ Fileを大量移動しない。

---

## 28. Open Items

次は未確定とする。

- `LFCaldix.exe`のRoot依存有無と最終配置
- `LFAssist.exe` / `LFAssist64.exe`をv1.7.x Active Runtimeとして残すか
- x86 Shell ExtensionをPublic Releaseへ含めるか
- `lficons.dll`の最終Path
- B2E Componentの最終Path
- v1.7.x Config Fileの正式保存形式とPath precedence
- Installer metadata / recovery cacheの最終配置
- Cache / Tempの既定PathとRetention
- Lifecycle Logの最終Path / ACL
- Uninstall時の`dll` / `cldx` / User Configuration削除UI

これらはPoCまたは関連設計Documentで確定し、本Documentへ反映する。

---

## 29. Directory Layout Principle

v1.7.xでは、Directoryを単なる整理目的で分けない。

各Pathが次を表すようにする。

```text
Who owns it?
Who may modify it?
Is it executable?
Is it user data?
May Repair overwrite it?
May Uninstall delete it?
Does writing require elevation?
```

最終的な原則は、

> User-facingなv1系の分かりやすさを残しながら、内部Runtime、External Backend、Legacy Asset、User Data、Temporary DataのOwnershipをPathレベルでも明確にする

ことである。
