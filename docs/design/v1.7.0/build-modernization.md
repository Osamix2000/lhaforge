# LhaForge v1.7.0 Build Modernization

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Development branch: `develop-v1.7.0`
- Purpose: v1.6.7のHistorical Buildを壊さずに観測しながら、再現可能な現代Buildへ段階的に移行する。
- Tooling evidence snapshot: 2026-07-29

Related documents:

- `design-review.md`
- `poc-plan.md`
- `risk-register.md`
- `architecture.md`
- `encoding.md`
- `security.md`
- `performance.md`

---

## 1. Goal

Build Modernizationの最初の目標はx64化ではない。

最初に、

> v1.6.7のSourceを現代の再現可能なToolchainでx86 Buildし、Historical Behaviorを比較できる基準点を作る

ことを目標とする。

その後、x64化、WTL更新、Security Mitigation強化等を独立した変更として進める。

```text
Historical v1.6.7 source
        ↓
Modern reproducible x86 build
        ↓
Regression baseline
        ↓
Dependency modernization
        ↓
Actual x64 build
        ↓
v1.7.x implementation
```

---

## 2. Existing Build Facts

現行`LhaForge.vcxproj`では、

```text
Debug|Win32       → v120_xp
Release|Win32     → v120_xp
Release-X64|Win32 → v120
```

が定義されている。

`Release-X64|Win32`もLinkerは、

```text
TargetMachine = MachineX86
```

であり、x64 Buildではない。

またProjectには、

```text
C:\Dev\vc2013\WTL90_4140_Final\Include
```

というMachine固有のWTL Pathが存在する。

`stdafx.h`には、

```cpp
#define _WIN32_WINNT 0x0600
#define _USE_32BIT_TIME_T
```

等のHistorical Assumptionが存在する。

これらを一括して変更せず、1項目ずつ影響を確認する。

---

## 3. Current Toolchain Direction

2026-07-29時点の開発Toolchain候補はVisual Studio 2026 stableとする。

Visual Studio 2026はVisual C++についてVisual Studio 2010以降のProjectを扱えるため、VS2013世代のLhaForge ProjectをModernizationする入口として利用可能である。

初期候補:

```text
IDE
  Visual Studio Community 2026 stable

Workload
  Desktop development with C++

Compiler
  MSVC Build Tools for x64/x86 (Latest stable)

Additional component
  C++ ATL for x64/x86

Windows SDK
  Windows 11 SDK 10.0.26100 familyを初期候補
```

Community Editionは個人開発およびOpen Source用途で利用可能なため、本Forkの標準開発IDE候補とする。

Preview ToolsetはBaseline Buildには使用しない。

---

## 4. Why Not Install VS2013 First

Historical Toolchainをそのまま再現することはEvidenceとして有用だが、v1.7.xのPrimary Development Environmentにはしない。

理由:

- Legacy Toolchain自体の保守性が低い
- 現代Windowsでの導入・再現性が低い
- x64 / Security / SDK Modernizationへ追加Migrationが必要になる
- Machine固有WTL Path問題を解決しない

必要になった場合はDisposable VM等でHistorical Buildを別途再現し、現代Buildとの比較Evidenceとして利用する。

---

## 5. Visual Studio Installation Policy

Developer個人のVisual Studio Installer選択に依存させない。

最終的にRepository Rootへ、

```text
.vsconfig
```

を追加し、必要ComponentをVersion Controlする。

初回PoCでは最低限、

- C++ Desktop Toolchain
- x86 / x64 MSVC
- ATL
- Windows SDK
- MSBuild / debugger

だけを要求する。

MFC、UWP、WinUI、C++/CLI、Linux Toolchain等は、LhaForge Buildに必要であることが確認されるまで必須にしない。

---

## 6. WTL Migration Strategy

現行ProjectはWTL 9.0.4140への固定Local Pathを使用している。

WTLのCurrent Stable候補は10.1.0であるが、Toolchain MigrationとWTL Major Updateを同時に実施しない。

### Stage A: Baseline Dependency

最初のModern x86 Buildでは、可能な限りHistorical Versionと同じ、

```text
WTL 9.0.4140
```

を再現可能なDependencyとして利用する。

候補:

```text
NuGet package: wtl 9.0.4140
```

目的はMachine固有Pathを除去しつつ、WTL Version差によるBehavior Changeを最初のBuildから混入させないことである。

### Stage B: WTL Upgrade

Modern x86 Regression Baseline成立後、別Commit / 別Testとして、

```text
WTL 10.1.0
```

へのUpgradeを評価する。

確認対象:

- Compile error / warning
- Window / Dialog behavior
- Message Map
- Common Control behavior
- DPI behavior
- Shell / COM interaction
- Binary size / startup

問題がある場合、v1.7.0でWTL 9.xを一時維持する選択も許容する。

---

## 7. Windows SDK Strategy

SDK VersionとMinimum supported Windows Versionを同一Decisionとして扱わない。

新しいWindows SDKでBuildしても、Runtimeで新APIを無条件に呼び出さなければ、より古いTarget OSを扱える場合がある。

したがって、

```text
Build SDK
Minimum Runtime OS
```

を分離する。

初期Build SDK候補は`10.0.26100` familyとし、PoC後にCurrent SDKへ更新するか判断する。

`10.0.28000` familyも2026年時点で提供されているが、Baseline BuildではSDK更新による変数を増やさず、まず安定した26100 familyを候補とする。

SDK Patch Buildは開発環境確定時に`.vsconfig` / Build Documentationへ記録する。

---

## 8. Minimum Windows Version

`_WIN32_WINNT 0x0600`はHistorical Baselineとして記録するが、v1.7.x Targetとして固定しない。

Visual Studio 2026のCurrent MSVCではWindows 7 / 8 / 8.1をLatest Toolset Targetとして扱わないため、Modern Buildの下限候補は少なくともWindows 10 / Windows Server 2016以降となる。

ただし、最終的に、

```text
Windows 10 compatibilityを維持するか
Windows 11を正式Minimumとするか
```

はAPI Audit、User Value、Test Costを見て決定する。

Minimum OSを決める前にSourceから、

- OS version checks
- deprecated API
- Shell Integration
- Common Controls
- Known Folder / Registry API
- DPI API
- Security API

をAuditする。

---

## 9. Configuration Cleanup

最終的なBuild Configurationは、少なくとも、

```text
Debug|Win32
Release|Win32
Debug|x64
Release|x64
```

を基本形とする。

ただし現行`Release-X64|Win32`は名前だけを理由に直ちに削除しない。

このConfigurationには、

- `v120`を使用
- `Release`は`v120_xp`
- PCH設定が`common.h`
- Optimization設定差

等が存在するため、作成意図とBehaviorを確認後に、

- 廃止
- 正しい名称へRename
- Historical ConfigurationとしてDocumentationのみ残す

のいずれかを決定する。

---

## 10. Runtime Library

現行Releaseは、

```text
RuntimeLibrary = MultiThreaded
```

を使用しており、Static CRT `/MT`相当である。

v1.7.xで、

```text
/MT
/MD
```

のどちらを採用するかはBaseline Build後に判断する。

最初のPoCではBehavior Differenceを減らすためHistorical設定を優先する。

Built-in Backend等Third-party Libraryを導入する段階でRuntime Library整合性を再検討する。

---

## 11. Compiler Warning Strategy

Modern Compilerへ移行するとLegacy Sourceから多数のWarningが出る可能性がある。

初回BuildでWarningを無理に0件へしない。

まず、

```text
Existing warning
New toolchain warning
Potential correctness issue
x64 blocker
Security relevant
Style only
```

へ分類する。

Security / correctness / x64 portabilityに関係するWarningから優先的に解消する。

Warningを一括DisableしてBuildを通すことはしない。

---

## 12. Security Mitigation Staging

Modern ToolchainのMitigationを利用するが、Baseline Buildと同時に全部変更しない。

候補:

- Buffer Security Check
- ASLR
- DEP / NX
- High Entropy VA for x64
- Control Flow Guard
- CET / hardware-enforced stack protection where applicable
- Spectre Mitigation Library where practical

Stage:

```text
Baseline x86
  ↓
Regression
  ↓
Mitigation one-by-one enable
  ↓
Regression / performance measurement
```

Security MitigationがLegacy DLL ABIを変えるものではないことも確認する。

---

## 13. Source Encoding During Build Migration

`encoding.md`の方針どおり、Build ModernizationのためにSource Tree全体を先にEncoding変換しない。

最初に、

- Compilerが現在のSourceをどう認識するか
- Resource Compiler
- Japanese String Literal
- Comment
- `.rc`
- Legacy Header

を確認する。

必要になったFileから段階的にUTF-8へ変更し、EncodingだけのCommitを分離する。

---

## 14. Reproducibility Requirements

Modern x86 Baseline Build完了時には、Clean Machineで次だけからBuildできる状態を目標とする。

```text
Git clone
+ Visual Studio / .vsconfig
+ Repository-declared dependency restore
+ documented build command
```

次を禁止する。

- `C:\Dev\...`等の個人Path
- 手動Copyしないと分からないHeader
- Version不明Dependency
- Build手順に記録されていないRegistry / Environment Variable依存

---

## 15. Initial Build Gate

PoC 1のExit Criteria:

1. Clean checkoutからx86 Debug / ReleaseがBuild可能。
2. Machine固有WTL Pathがない。
3. Build Tool / SDK / WTL Versionが記録されている。
4. Applicationが起動する。
5. v1.6.7の基本UIが表示される。
6. Basic Archive OperationをRegression確認できる。
7. Known Warning / Difference一覧が存在する。
8. Source Encodingを無関係に大量変更していない。
9. x64化や新機能をまだ混入させていない。

---

## 16. Proposed Change Sequence

```text
BM-001
Add build documentation / .vsconfig

BM-002
Remove machine-specific WTL include path
and restore WTL 9.0.4140 reproducibly

BM-003
Retarget x86 project to modern MSVC / SDK

BM-004
Fix compile blockers only

BM-005
Produce Debug / Release x86 binaries

BM-006
Run v1.6.7 regression baseline

BM-007
Evaluate WTL 10.1.0 separately

BM-008
Normalize project configurations

BM-009
Start actual x64 configuration
```

個々を可能な限り独立Commitにし、Regressionの原因を追跡可能にする。

---

## 17. User Preparation

このDocument作成時点では、User側でVisual Studioをまだ導入しなくてよい。

次に`.vsconfig`と具体的なInstallation ChecklistをRepositoryへ追加した時点を、開発環境準備開始のGateとする。

旧Visual Studio、v120、v120_xp、WTL 9.0を手作業で先に導入しない。

---

## 18. Open Items

- Visual Studio 2026の導入Component最終一覧
- `.vsconfig`の最終Component ID
- Windows SDK 26100 familyの具体的Patch Version / Installer availability
- Minimum supported Windows Version
- WTL 9.0.4140 NuGet Restoreの現行MSBuild上での動作
- WTL 10.1.0へのUpgrade時期
- `/MT`継続か`/MD`移行か
- Warning Levelの最終値
- Spectre / CFG / CET等のRelease既定
- Historical `Release-X64|Win32`の意図と廃止時期
- CI Build環境

これらはPoC 1開始前または該当Phase直前に確定する。
