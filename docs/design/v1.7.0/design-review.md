# LhaForge v1.7.0 Design Review

- Status: Draft
- Review cycle: 1
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Integration branch: `main-osamix`
- Development branch: `develop-v1.7.0`
- Purpose: 実装開始前に設計文書を横断し、矛盾、古いTBD、実装前Blocker、PoC対象を整理する。

Related documents:

- `architecture.md`
- `ownership-matrix.md`
- `directory-layout.md`
- `archive-operations.md`
- `backend.md`
- `migration.md`
- `installer.md`
- `logging.md`
- `encoding.md`
- `security.md`
- `performance.md`
- `signing.md`
- `poc-plan.md`
- `risk-register.md`
- `build-modernization.md`

---

## 1. Review Result

Review cycle 1時点では、v1.7.0設計を破棄・再設計する必要がある重大なArchitecture矛盾は確認していない。

次のCore Principleは文書間で整合している。

1. v1.6.7を直接の開発Baselineとする。
2. v1系UI、操作性、外部アーカイバDLL文化を維持する。
3. Main Applicationはx64化し、x86 DLLはLegacyHostで利用する。
4. Backend優先順位はExternal x64 → External x86 + LegacyHost → Built-inとする。
5. Backendは存在だけでなくCapabilityとSecurity条件を満たした場合のみ選択する。
6. Archive Path Security、Input Filter、Resource Limit等はBackend共通Policyとする。
7. Program Files等へのSystem-wide変更だけを必要時にElevationする。
8. Code Signingは利用可能なArchitectureとするが、Application動作の必須条件にはしない。
9. Installer / MigrationはOwnership、Journal、Rollbackを基礎とし、既存環境を先に破壊しない。
10. External DLL、`cldx`、User Configuration、Unknown Fileを無条件削除・上書きしない。
11. Internal StringはUnicodeを基本とし、Legacy EncodingはBoundaryで扱う。
12. Securityを無効化してPerformanceを得る設計にはしない。

したがって、次の段階ではArchitectureの全面再検討ではなく、Build Modernizationへ進むためのDecision GateとPoCを消化する。

---

## 2. Source Baseline Findings

設計レビューと同時に、現行v1.6.7 Project FileからBuild Baselineを再確認した。

### 2.1 Visual Studio / Toolset

`LhaForge.sln`のSolution metadataはVisual Studio 2013世代である。
一方、`LhaForge.vcxproj`は`ToolsVersion=15.0` / `_ProjectFileVersion=15.x`で、公式`source.txt`はVisual Studio 2017 CommunityをDevelopment Environmentとして明記する。

したがって「最終開発環境がVS2013だった」とは断定せず、VS2017上でv120 / v120_xp Toolsetを使用していた可能性をBaseline Evidenceとして扱う。

```text
VisualStudioVersion = 12.0.40629.0
MinimumVisualStudioVersion = 10.0.40219.1
```

`LhaForge.vcxproj`では、主に次のToolsetを使用している。

```text
v120
v120_xp
```

これはHistorical Baselineとして保持するが、v1.7.xの開発環境として旧Toolsetをそのまま採用する理由にはしない。

### 2.2 WTL Path Dependency

Project Fileには次のような開発者環境固有Pathが存在する。

```text
C:\Dev\vc2013\WTL90_4140_Final\Include
```

したがって現在のProjectはClean Machineでそのまま再現できるBuild定義ではない。

一方、公式`source.txt`ではDevelopment Environmentを`Visual Studio 2017 Community / WTL 9.1 Final`としている。Project File自体も`ToolsVersion=15.0`であるため、固定Directory Nameだけを根拠に9.0.4140を最終利用Versionと断定できない。

BM-002ではWTL 9.1.5321をPrimary、9.0.4140をCompatibility Profileとして両方Restore可能にし、このEvidence conflictをPoC Buildで検証する。

### 2.3 `Release-X64`はx64 Buildではない

`LhaForge.vcxproj`には`Release-X64`というConfiguration名があるが、Project Platformは`Win32`である。

```text
Release-X64|Win32
```

ただしこのConfigurationには、`Release|Win32`の`v120_xp`に対して`v120`を使うことや、PCH設定などの差がある。したがって名称だけを理由に削除・Renameせず、Historical意図をBaseline Buildで確認してから整理する。

Linker設定も次の通りである。

```text
TargetMachine = MachineX86
```

さらに現行`LhaForge.sln`が公開するConfigurationは、

```text
Debug|Win32
Release|Win32
```

のみである。

したがって、v1.6.7 Baselineに「実用可能なx64 Main Application Buildが既に存在する」と解釈してはならない。

v1.7.xのx64化は明示的なMigration Taskである。

### 2.4 Windows / Time Assumptions

`stdafx.h`には少なくとも次が存在する。

```cpp
#define _WIN32_WINNT 0x0600
#define _USE_32BIT_TIME_T
```

これらはHistorical Behaviorに関わるため、単純削除ではなく、

- Minimum Windows Version
- 現代Windows SDK
- x64 Build
- Date / Time handling
- Archive metadata

との関係をBuild Modernization PoCで確認する。

### 2.5 Source Encoding

Legacy SourceにはCP932系とみられる日本語Comment / Resourceが存在する。

Build Modernizationの最初の段階では、Sourceを一括UTF-8変換することを目的にしない。

最初にModern Toolchain上でBaseline Behaviorを再現し、その後必要なEncoding Modernizationを段階的に行う。

---

## 3. Resolved Stale TBDs

Installer Designが追加されたことで、Ownership Matrixの次のUninstall PolicyはReview cycle 1で確定可能となった。

### User Configuration

`LhaForge.ini`:

```text
Default uninstall
    Preserve

Explicit cleanup selected by user
    Delete allowed
```

### Shared Compatibility Configuration

`LFCaldix.ini`:

```text
Default uninstall
    Preserve

Explicit cleanup
    Ownership / dependencyを確認した上で削除可能
```

### `cldx`

```text
Default uninstall
    Preserve

Explicit cleanup
    Userが明示選択した場合のみ削除
```

### External Archive DLL

```text
Default uninstall
    Preserve

Explicit cleanup
    Userが明示選択した場合のみ削除
```

Unknown ownershipやUser supplied FileをInstaller都合で削除しない原則は維持する。

---

## 4. Cross-document Consistency Check

| Area | Review result | Notes |
| --- | --- | --- |
| Baseline | Consistent | `ver_1_6_7`を不変Baselineとして利用 |
| Branch model | Consistent | `main-osamix` / `develop-v1.7.0` |
| Backend priority | Consistent | x64 External → x86 LegacyHost → Built-in |
| Capability model | Consistent | FormatだけでなくOperation / Capability / Securityで選択 |
| Compression exclusion | Consistent | Final Input SetをLhaForge側で確定 |
| Extraction destination | Consistent | Logical Archive Nameを共通層で生成 |
| Privilege | Consistent | Normal operationはnon-elevated、必要箇所のみElevation |
| Signing | Consistent | Optional、Provider非依存 |
| Migration | Consistent | In-place default、Backup / Journal / Rollback |
| Uninstall ownership | Updated | User data / external assetsはDefault preserve |
| Logging | Consistent | Runtime LogとLifecycle Journalを分離 |
| Encoding | Consistent | Unicode Core + Legacy Boundary |
| Security | Consistent | Backend共通Guard、unsafe fallback禁止 |
| Performance | Consistent | bounded resource、不要なcopy / scanを避ける |

---

## 5. Decision Gates Before Implementation

すべてのOpen Itemを実装開始前に確定する必要はない。

実装Phaseごとに必要なDecisionだけをGateとして扱う。

### Gate A: Build Modernization開始前

Gate AはEnvironment SetupとProject Retargetを分離する。

#### Gate A1: Development Environment Setup

Status: **Resolved**

確定済み:

- Visual Studio Community 2026 Stable
- v143 / MSVC 14.44 family
- Windows SDK 26100 family
- ATL v14.44
- WTL Primary 9.1.5321 / Compatibility 9.0.4140
- Repository Root `.vsconfig`
- `tools/verify-vs-environment.ps1`

この時点から開発PCへ`.vsconfig`に従ってVisual Studioを導入してよい。

#### Gate A2: First Modern x86 Retarget

確定が必要:

- WTL 9.1.5321 / 9.0.4140のRepository-managed RestoreとA/B Build結果
- Source Encodingを壊さないProject Retarget手順
- x86 Baseline Configuration名とOutput Layout

Minimum supported Windows VersionはPoC 1のCompiler再現に必須ではないため、このGateから分離する。現時点では新APIを無条件導入せず、Runtime OS方針はAPI Audit後に確定する。

### Gate B: x64 Migration開始前

確定が必要:

- x86-specific type / pointer / time assumptions audit
- x64 Project Configuration
- Main ApplicationとLegacyHostの責務境界
- External x64 DLLの最初のPoC対象

### Gate C: Backend Abstraction開始前

確定が必要:

- Common Backend Interfaceの最小型
- Capability Model
- Format Detectionの最小Contract
- Error / Cancellation / Progress Model

Built-in Libraryの最終選定は、この時点で全Format分を確定する必要はない。

### Gate D: LegacyHost実装前

確定が必要:

- IPC Wire Format
- Version negotiation
- Timeout / cancellation
- Host lifetime
- Crash / fault quarantine
- Path / payload validation

### Gate E: Installer / Migration実装前

確定が必要:

- Installer Framework
- Manifest / Install State Format
- Lifecycle State Path / ACL
- Shell locked-file policy
- Recovery Payload方針
- Legacy Registry Inventory

### Gate F: Public Release前

確定が必要:

- Signing採用有無
- Release Artifact / Hash policy
- Update distribution
- Third-party license / redistribution check
- Supported Backend Matrix
- Minimum Windows Versionの最終表記

---

## 6. Items That Can Remain Deferred

次は現時点で確定不要である。

- Public Code Signing Provider
- Full Built-in Format Matrix
- Safe Modeの最終UI
- Diagnostic Bundle搭載有無
- Full Path Diagnostic UI
- Per-user Install
- Explicit Relocation Upgrade
- x86 Shell ExtensionをPublic Releaseへ含めるか
- Advanced Backend Preference UI
- `.gitignore` Import機能

これらを早期に固定すると、PoC結果による選択肢を狭める可能性がある。

---

## 7. Priority Findings

### High: Reproducible Buildがまだ存在しない

現在のProjectはVS2013 Solution metadata、VS2017世代Project metadata、v120 / v120_xp Toolset、hard-coded WTL Pathが混在しており、そのままではClean Machine Buildを再現できない。

最優先はModern x64化ではなく、

> Cleanな現代環境でv1.6.7相当のx86 Buildを再現できる状態

を作ることである。

### High: `Release-X64`名称を信用しない

名称とは異なりx86 Buildであるため、Build Modernization時にConfigurationを整理する。

### High: x86 Assumption Audit

Pointer sizeだけでなく、`time_t`、Window Message payload、Struct packing、DLL API、Registry / Shell Integration等を対象にする。

### High: External DLLはTrust Boundary

Compatibilityのため外部DLLを優先するが、外部DLLをFirst-party codeと同じTrust Levelとして扱わない。

### High: Migration / InstallerはData Lossを起こさないことを最優先

Unknown File、External DLL、`cldx`、User ConfigurationをDefault preserveする。

### Medium: Legacy Component Source Integration

現行SolutionはMain `LhaForge` Projectを中心としている。

MenuEditor、Unregister、LFAssist、Shell Extension、LFCaldix等はHistorical Sourceも含めて、PhaseごとにBuild対象へ統合する方法を決める。

### Medium: Source Encoding CleanupはBuild Stabilization後

文字化けを直すための大規模ConversionをBuild Modernizationと同時に行わない。

---

## 8. Current Readiness

現状:

```text
Legacy evidence             Ready
Core architecture           Ready for PoC
Ownership model             Ready for PoC
Backend model               Ready for PoC
Security model              Ready for PoC
Migration / Installer model Ready for PoC
Build environment           Not selected yet
Reproducible modern build   Not available yet
Actual x64 build            Not available yet
```

したがって次の実作業は、`poc-plan.md`に従ってBuild Modernization Gateを準備する。

---

## 9. Review Exit Criteria

Design Review cycle 1は次を満たした時点で終了とする。

1. Major Architecture間に既知の矛盾がない。
2. 古いTBDが現在の設計に合わせて更新されている。
3. 実装前BlockerとDeferred Itemを区別できている。
4. PoC順序が定義されている。
5. Risk Registerに主要Riskが登録されている。
6. Build Modernization開始時にUser側へ要求する環境が明示できる。

この時点でSource Codeの全面変更は要求しない。
