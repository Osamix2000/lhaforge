# LhaForge v1.7.0 Architecture

* Status: Draft
* Target: LhaForge v1.7.x
* Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
* Integration branch: `main-osamix`
* Development branch: `develop-v1.7.0`

Related ADR:

* ADR-0001: v1.6.7を開発基準とする
* ADR-0002: v1系外部DLL互換を維持する
* ADR-0003: x64本体とLegacyHostを採用する
* ADR-0004: Built-in BackendをFallbackとして持つ
* ADR-0005: 署名可能なRelease Architectureと最小権限設計を採用する

Related design documents:

* `ownership-matrix.md`
* `archive-operations.md`
* `signing.md`
* `security.md`
* `performance.md`
* `directory-layout.md`
* `backend.md`
* `migration.md`
* `installer.md`（予定）
* `logging.md`（予定）
* `encoding.md`（予定）

---

## 1. Purpose

LhaForge v1.7.xは、LhaForge v1.6.7を直接の基盤として、v1系のUI・操作性・外部アーカイバDLLとの互換性・Legacy Format対応を可能な限り維持しながら、現代のWindows環境向けに内部設計をModernizeする。

目的はLhaForge v2をv1風UIへ変更することではなく、

```text
LhaForge v1.xの思想・操作性・互換性
                +
現代Windows向けの安全性・保守性・可用性
                =
LhaForge v1.7.x
```

を実現することである。

---

## 2. Architecture Goals

v1.7.xでは、主に次を実現する。

### Compatibility

* LhaForge v1系UI・操作性の継承
* 統合アーカイバDLLとの互換性維持
* 既存v1.6.7環境からのMigration
* Legacy Formatへの対応
* MenuEditor、LFCaldix等のv1系運用文化の継承

### Modernization

* LhaForge本体のx64化
* 現代MSVC / Windows SDKによるBuild
* Unicodeを基本とした内部処理
* DPI・現代Windows UIへの対応
* DLLロード方式の安全化
* Archive Path Securityの強化
* Logging基盤の新設
* Installer / Repair / Update / Uninstallの再設計
* 必要な操作だけを昇格するLeast Privilege設計
* Signed / Unsigned双方を許容するRelease Architecture

### Availability

* External DLLが利用できない場合のBuilt-in Backend
* x86専用DLLを継続利用するLegacyHost
* Backend障害時の明確な診断
* Repair / Recovery経路の確保

### Security and Performance

* Backend種別に依存しない共通Security Policy
* 圧縮前に最終Input Setを確定し、`.git`や`.env`等の誤共有を防止できる除外Policy
* Archive名を安全に利用した展開先Directory生成
* 不要なFilesystem再ScanやData Copyを避けるOperation Planning
* 大量File、巨大Archive、異常Archiveを考慮したResource Management

---

## 3. Non-Goals

v1.7.xでは、次を主目的としない。

* LhaForge v2 Architectureへの移行
* v1系外部DLL方式の廃止
* UIの全面的な再設計
* Web技術によるUIへの置換
* v1.6.7の挙動を完全に無条件で再現すること
* 安全性を犠牲にしてLegacy Behaviorを維持すること
* 初期段階でのPortable Edition提供

Legacy CompatibilityとSecurityが競合する場合は、差異を文書化した上でSecurityを優先する。

---

## 4. High-Level Architecture

```text
┌──────────────────────────────────────────────┐
│                LhaForge.exe x64              │
│                                              │
│  ┌──────────────┐    ┌───────────────────┐  │
│  │      UI      │    │   Configuration   │  │
│  └──────┬───────┘    └─────────┬─────────┘  │
│         │                      │            │
│         └──────────┬───────────┘            │
│                    ▼                        │
│          ┌───────────────────┐              │
│          │ Operation Planner │              │
│          └─────────┬─────────┘              │
│                    ▼                        │
│            ┌───────────────┐                │
│            │ ArchiveManager│                │
│            └───────┬───────┘                │
│                    │                        │
│       ┌────────────┼────────────┐           │
│       ▼            ▼            ▼           │
│ External x64   External x86   Built-in      │
│   Backend        Backend       Backend       │
│       │              │                       │
│       ▼              ▼                       │
│ dll\x64\      LegacyHost.exe x86            │
│                      │                       │
│                      ▼                       │
│                  dll\x86\                    │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Security / Logging / Compatibility Core │ │
│ └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘

周辺コンポーネント

├─ MenuEditor.exe
├─ Unregister.exe
├─ LFCaldix.exe
├─ Shell Extension
├─ LFAssistant系Compatibility
├─ Installer / Updater
└─ Uninstaller / Recovery
```

---

## 5. Main Application

`LhaForge.exe`をv1.7.xの中心Applicationとする。

最終的な本体Architectureはx64を基本とする。

主な責務:

* UI
* ユーザー操作受付
* Configuration管理
* Archive Format判定
* Backend選択
* Archive Operation管理
* Security Policy適用
* Logging
* Error Handling
* Legacy Componentとの連携

Archive処理固有の実装をUIへ直接結合しない。

UIはArchiveManager等のApplication Layerを経由して操作する。

---

## 6. ArchiveManager

ArchiveManagerはArchive処理の中心となり、

> どのBackendで処理するか

を決定する。

Backendの実装方式ではなくCapabilityを基準とする。

代表的なCapability:

```text
Open
List
Test
Extract
Create
Update
Delete
Password
Encryption
MultiVolume
Unicode
ExactInputSet
InputList
```

例えばZIPを扱えるBackendであっても`Extract`のみ対応し`Create`に対応しない場合は、圧縮時には別Backendを選択できる。

### Operation Planning

User-facingな圧縮・展開PolicyはBackend固有実装へ直接持たせず、ArchiveManagerへ渡す前にOperation Plannerで処理する。

```text
User Operation
      ↓
Operation Planner
      ├─ Input Enumeration
      ├─ Exclusion Policy
      ├─ Destination Policy
      ├─ Security Validation
      └─ Operation Plan
              ↓
        ArchiveManager
```

圧縮時はDirectory Treeを可能な限り一度だけ列挙し、除外Ruleを適用した最終Input Setを確定してからBackendへ渡す。

除外Modeとして少なくとも次を扱う。

* 除外しない
* Rule一致項目を自動除外
* 圧縮時に一致項目を確認して決定

`.git`、`.env`等の初期Ruleに加え、ユーザーがOption画面から除外Ruleを追加・削除・有効化・無効化できる構造とする。

除外が有効な場合、Backendが独自に元Directoryを再列挙して除外対象をArchiveへ追加してはならない。最終Input Setを正確に扱えないBackendではFiltered Createを利用不可とする。

展開時にはArchive名を利用したSubdirectory作成を共通Policyとして提供する。`source.tar.gz`を`source\`へ展開する等、Format Registryが認識する最長SuffixやMulti-volumeのLogical Nameを利用し、安全なDirectory名へ変換する。

詳細は`archive-operations.md`で定義する。

---

## 7. Backend Architecture

基本優先順位:

```text
1. External x64 Backend
        ↓ unavailable / unsupported

2. External x86 Backend + LegacyHost
        ↓ unavailable / unsupported

3. Built-in Backend
        ↓ unavailable / unsupported

4. Error
```

ただし単純にファイルが存在するだけではBackendを利用可能と判定しない。

少なくとも、

* DLL存在
* PE Architecture
* Load可能性
* Export
* API Version
* 初期化
* Capability
* Compatibility

を確認する。

詳細は`backend.md`で定義する。

---

## 8. External x64 Backend

64bit対応版が存在する統合アーカイバDLL等は、LhaForge x64本体から直接利用する。

配置先の基本案:

```text
dll\
└─ x64\
```

External DLLはManaged Runtime内部へ隠さず、v1系の特徴を継承したUser-serviceable Backendとして扱う。

ユーザーによるDLLの確認・交換を許容する。

そのためInstallerやRepairは、既存DLLを無条件に上書きしない。

---

## 9. LegacyHost

32bit DLLを64bit LhaForgeから利用するため、

```text
LhaForgeLegacyHost.exe
```

をx86 Processとして用意する。

```text
LhaForge.exe x64
       │
       │ Named Pipe
       ▼
LhaForgeLegacyHost.exe x86
       │
       ▼
External x86 DLL
```

LegacyHostはCompatibility Bridgeであり、第二のLhaForge本体とはしない。

UI、Configuration、Backend Selection、Security Policy等は本体側へ集約する。

LegacyHostでは、

* DLLロード
* API呼び出し
* Operation実行
* Progress
* Result
* Error

等の必要最小限の処理を担当する。

Archive Data本体をIPCで転送せず、LegacyHost / DLLがFilesystemへ直接アクセスする。

---

## 10. Built-in Backend

主要Archive形式について、External DLLが存在しなくても基本操作を提供する。

初期目標:

* ZIP
* 7z
* TAR
* gzip
* bzip2
* XZ
* LZMA
* Zstandard
* RAR / RAR5の読み取り・展開

Built-in BackendはExternal DLLを置き換えるものではなくFallbackである。

Archive Libraryの具体的な採用は別途評価する。

libarchiveを中心とした構成を有力候補とするが、本ArchitectureではLibraryを固定しない。

---

## 11. Security Layer

Archive Backend固有処理とSecurity Policyを可能な限り分離する。

External DLL、LegacyHost、Built-in Backendのいずれを使用しても、LhaForge側で可能な範囲の共通Security Validationを行う。

主な対象:

* Path Traversal
* Absolute Path
* Drive Path
* UNC Path
* Device Path
* NTFS ADS
* Reserved Name
* Trailing Dot / Space
* Symlink
* Junction
* Reparse Point
* Unicode Control Character
* Temp Directory
* Resource Exhaustion
* Archive Bomb
* 圧縮対象のSecret / Unwanted File除外Policy
* Filtered Create時の最終Input Set保証

DLLロードについても、

* Absolute Path
* Architecture Validation
* Search Path制限
* API / Export Validation

を行う。

詳細は`security.md`で定義する。

---

## 12. Configuration

v1.6.7とのCompatibilityを維持しながら、Configuration AccessをApplication内部で統一する。

Legacy対象:

```text
LhaForge.ini
LFCaldix.ini
```

`LFCaldix.ini`はLFCaldixだけの専有設定とはみなさず、LhaForge本体とのShared Compatibility Configurationとして扱う。

v1.7.xでは、

```text
Configuration Layer
        │
        ├─ v1 Legacy Config Reader
        ├─ Current Config
        └─ Migration
```

のように、保存形式とApplication Logicの直接結合を減らす。

Legacy Fileの存在場所・Encoding・Migrationルールは別途定義する。

圧縮・展開の共通設定として、少なくとも次をConfiguration Layerから管理可能にする。

* 圧縮時の除外Mode
* 除外Rule List
* Ruleの有効/無効
* Archive名Directoryへ展開するPolicy
* 展開先Collision Policy

個別Backendの設定形式へ直接依存させず、Backend Adapterが共通設定をCapabilityに応じて実行可能な形式へ変換する。

---

## 13. Encoding

Application内部ではUnicodeを基本とする。

Windows APIは可能な限りWide Character APIを利用する。

Legacy DLLがANSI API等を要求する場合のみCompatibility Boundaryで変換する。

Application自身が管理するTextについては、

* UTF-8
* UTF-8 BOM
* UTF-16 LE
* UTF-16 BE
* CP932 / Shift_JIS

等、Legacy Dataを考慮する。

改行についても、

* CRLF
* LF
* CR

を適切に認識する。

Archiveから展開したユーザーファイルのEncodingや改行をLhaForgeが勝手に変換してはならない。

詳細は`encoding.md`で定義する。

---

## 14. Logging

v1.7.xでは共通Logging Coreを設ける。

```text
Logging Core
    │
    ├─ FileLogSink
    └─ WindowsEventLogSink
```

LhaForge内部Log Level:

1. Emergency
2. Alert
3. Critical
4. Error
5. Warning
6. Notice
7. Info
8. Debug
9. Trace

File LogとWindows Event Logは出力先を独立して有効化でき、それぞれ別の最低Levelを設定可能とする。

通常処理の詳細はFile Logを中心とし、Windows Event Logへ過剰な情報を記録しない。

詳細は`logging.md`で定義する。

---

## 15. UI Architecture

v1.7.xはv1.6.7の操作性を基準とする。

全面的なUI再設計は行わない。

現代化対象:

* Common Controls v6
* DPI対応
* Per-Monitor DPI
* 現代WindowsのNative Frame
* Font Metric対応
* Layout調整
* Unicode表示
* Dialog改善

日本語UIについては`Yu Gothic UI`等の現代Windows標準UIに適したFontを検討する。

独自描画Title Bar等によるWindows標準UIの再実装は原則行わない。

Dark Modeはv1.7.0初期目標から除外するが、将来Themeを追加できないArchitectureにはしない。

---

## 16. Legacy Components

次のv1系Componentについて、役割を調査・維持する。

```text
MenuEditor.exe
Unregister.exe
LFCaldix.exe
LFAssist.exe
LFAssist64.exe
ShellExtDLL.dll
ShellExtDLL64.dll
```

すべてをそのまま残すことを意味しない。

v1.7.xでは、

* User-facing compatibility
* Internal implementation
* Migration input
* Legacy only

をOwnership Matrixに基づき分類する。

`MenuEditor.exe`および`Unregister.exe`のようなv1で認識されてきたUser-facing Componentは、可能な限りv1.7.xでも明示的に維持する。

---

## 17. Shell Integration

Shell ExtensionはLhaForge本体と分離する。

x64 Windowsを基本対象とし、64bit ExplorerとのIntegrationを中心に再設計する。

Registry Registration、Association、Shell Menu等は直接各Componentが独自実装するのではなく、可能な範囲で共通管理へ移す。

旧LFAssistantの役割はLegacy Baselineとして保持しつつ、v1.7.xでの責務は別途決定する。

---

## 18. LFCaldix and cldx

LFCaldixはv1系External DLL運用を構成するLegacy Componentとして扱う。

`cldx`は単純なRuntime DLL Directoryではない。

旧LFCaldixが取得したDLLの説明書・関連資料等を保存するLegacy Managed Asset領域として扱う。

v1.7.xでは、

```text
dll\
    実際に使用するExternal Backend

cldx\
    LFCaldix由来の説明書・関連資料・Legacy Asset
```

を分離する。

MigrationやRepairで`cldx`をTemporary Cacheとして無条件削除してはならない。

---

## 19. Installer Architecture

v1.7.xではInstaller、Repair、Upgrade、Uninstallを一体のLifecycleとして設計する。

基本原則:

1. 既存環境を先に破壊しない
2. 新しい状態を準備してから切り替える
3. Validationする
4. 失敗時にRollback可能にする
5. User Data / User-managed DLLを無条件上書きしない
6. 削除処理は最後に行う
7. Original Setup.exeへRoutine Operationを依存させない
8. 変更内容をLoggingする

Uninstall Architecture案:

```text
Uninstall.exe
    User-facing Recovery Launcher

runtime\installer\UninstallCore.exe
    Standalone Uninstaller Core
```

WindowsのUninstall Registrationは、可能な限り`UninstallCore.exe`へ直接到達できる構成とする。

### Privilege Separation and Optional Signing

通常のLhaForge本体、Archive操作、設定等は一般ユーザー権限を基本とする。Program Files、HKLM、Machine-wide Shell登録等、本当に必要なSystem変更だけを専用Core / Helperで明示的にElevationする。

```text
Unelevated
    LhaForge.exe / UI / Archive Operations
           │
           │ System-wide変更時のみElevation
           ▼
Elevated
    Install / Repair / Update / Uninstall Core
```

Authenticode署名は導入可能なRelease機能として設計するが、v1.7.xの正常動作やRelease成立の必須条件にはしない。Signed / Unsignedの双方を同じBuild / Package設計で扱えるようにし、署名が利用できる場合は追加のPublisher / Integrity Validationとして活用する。

署名なしの場合でもHash、Manifest、Expected Path、Version等によるIntegrity確認を可能な範囲で行う。

詳細は`signing.md`およびADR-0005で定義する。

詳細は`installer.md`で定義する。

---

## 20. Migration

v1.6.7からv1.7.0へのUpgradeは通常のFile Overwriteとはせず、Migrationとして扱う。

基本Flow:

```text
Detect
  ↓
Inspect
  ↓
Backup / Snapshot
  ↓
Prepare
  ↓
Migrate
  ↓
Validate
  ↓
Register
  ↓
Commit
  ↓
Cleanup
```

対象:

* Install Path
* Configuration
* Registry
* File Association
* Shell Extension
* External DLL
* LFCaldix
* cldx
* User-modified files

所有主体が不明なファイルは原則保持する。

詳細は`migration.md`で定義する。

---

## 21. Installation Layout

現時点の概念案:

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
│  ├─ shell\
│  ├─ assistant\
│  ├─ installer\
│  └─ update\
│
├─ resources\
└─ licenses\
```

この構造の配置Policy、Ownership、書き込み可能Data領域、Repair / Migration / Uninstall時の扱いは`directory-layout.md`で定義する。

個々のLegacy Componentについて技術制約が判明した場合は、PoC結果を基に`directory-layout.md`を更新する。

---

## 22. Dependency Rules

可能な限り次の依存方向を維持する。

```text
UI
 ↓
Application / ArchiveManager
 ↓
Backend Abstraction
 ↓
Backend Implementation
```

逆方向の依存を避ける。

特に、

* BackendからUIを直接操作しない
* LegacyHostへBusiness Logicを持たせない
* Installer固有処理をApplication Runtimeへ混在させない
* Security PolicyをBackendごとに複製しない
* Logging実装を各Subsystemへ直接埋め込まない

ことを基本とする。

---

## 23. Failure Handling

異常発生時は、

```text
Detection
↓
Classification
↓
Logging
↓
Safe cleanup
↓
Fallback / Abort
```

を基本とする。

Fallback可能性はOperation開始前と開始後で区別する。

Archive展開・作成等でFilesystemへ変更を開始した後に、別Backendで無条件に自動再実行しない。

部分生成物、上書き状態等を考慮して判断する。

---

## 24. Compatibility Policy

Compatibilityを次の3種類に分ける。

### User Compatibility

* UI
* 操作性
* Settings
* Shell integration
* File association

### Archive Compatibility

* Formats
* External DLL API
* Filename / Encoding
* Metadata

### Environment Compatibility

* v1.6.7 Installation
* Registry
* LFCaldix
* cldx
* User-modified DLL

「Compatibility」という理由だけで過去の危険な実装をそのまま維持しない。

---

## 25. Development Strategy

実装は一度に全面Rewriteしない。

基本Phase:

```text
Phase 1
Legacy Baseline / Design

Phase 2
Build Modernization

Phase 3
Existing v1.6.7 Behavior Regression

Phase 4
x64 Main Application

Phase 5
Backend Abstraction

Phase 6
LegacyHost

Phase 7
Built-in Backend

Phase 8
Security / Performance / Logging / Encoding modernization

Phase 9
Installer / Migration / Recovery

Phase 10
UI modernization / Final compatibility work
```

各Phaseで動作確認可能な状態を維持する。

---

## 26. Open Items

現時点で未確定の主な項目:

* Windows最低対応Version
* Modern MSVC / Windows SDK Version
* WTL Version
* Built-in Backend Library構成
* Individual External DLL Support Matrix
* LegacyHost IPC Protocol詳細
* Final Installation Layout
* Configuration保存形式
* Shell Extension Architecture詳細
* Installer Framework
* Update Distribution方式
* Public ReleaseでのCode Signing採用有無 / Signing Provider
* Compression Exclusion Rule Syntax / Default Rule Set
* Extraction Destination Collision Policy
* Safe Mode正式仕様

これらは調査・PoC・個別設計後に確定する。

---

## 27. Architecture Principle

v1.7.xにおける基本判断基準は、

> v1系の価値を維持しながら、内部実装を現代Windowsに適した安全で保守可能な構造へ更新できるか

とする。

Legacy Compatibility、Security、Performance、Reliability、Recoverability、Maintainabilityのバランスを取り、単なる「古いLhaForgeの再ビルド」ではなく、

> LhaForge v1系を継続可能な形へModernizeする

ことをArchitecture全体の目的とする。
