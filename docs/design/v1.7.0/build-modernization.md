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
- `development-environment.md`
- `dependencies.md`

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

Visual Studio 2026をModernizationの入口とする。LhaForgeはSolution metadataがVS2013、Project metadataがVS2017世代、Toolsetがv120 / v120_xpという混在状態のため、IDE世代とCompiler Toolsetを分離して扱う。

PoC 1の標準環境を次のように確定する。

```text
IDE
  Visual Studio Community 2026 Stable

Workload
  Desktop development with C++

Baseline compiler
  MSVC 14.44 compiler family
  x86 / x64 Build Tools

ATL
  ATL for MSVC 14.44

Windows SDK
  Windows 11 SDK 10.0.26100 family

Target Platform Version candidate
  10.0.26100.0
```

Visual Studio 2026で提供されるLatest MSVCをPoC 1のBaselineには使用せず、MSVC 14.44を`VCToolsVersion`で明示的に固定する。MSBuild統合にはVS2026の`PlatformToolset v145`を使用する。IDE更新とCompiler世代更新を分離し、Modern x86 Regression成立後にLatest MSVCを別Changeとして評価する。

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

Repository Rootの`.vsconfig`を標準Installation ConfigurationとしてVersion Controlする。

PoC 1の`.vsconfig`では、次を明示する。

```text
Microsoft.VisualStudio.Workload.NativeDesktop
Microsoft.VisualStudio.ComponentGroup.VC.Tools.143.x86.x64
Microsoft.VisualStudio.Component.VC.14.44.17.14.ATL
Microsoft.VisualStudio.Component.Windows11SDK.26100
Microsoft.VisualStudio.Component.NuGet
```

MSBuild / debugger等はC++ Desktop Workloadから取得する。

MFC、UWP、WinUI、C++/CLI、Linux Toolchain等は、LhaForge Buildに必要であることが確認されるまで必須にしない。

---

## 6. WTL Migration Strategy

現行Projectは`WTL90_4140_Final`という固定Local Pathを使用している一方、公式`source.txt`はDevelopment Environmentとして`WTL 9.1 Final`を明記する。

したがってPath名だけから9.0.4140を最終Baselineと断定しない。

### Stage A: Reproducible Historical Profiles

BM-002ではOfficial SourceForge ArchiveをSHA-256で固定し、次の2 ProfileをRepository-managed Restoreする。

```text
Primary:       WTL 9.1.5321 Final
Compatibility: WTL 9.0.4140 Final
```

Primaryは`source.txt`を優先する。9.0.4140はProject Fileに残るHistorical Pathの意味を検証するためのA/B Profileとする。

目的はMachine固有Pathを除去しつつ、WTL Version Evidenceの不一致をBuild結果で解消可能にすることである。

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

## 15. BM-003 Retarget Applied

### 15.1 First Build Finding

初回`Debug|Win32` Buildでは`MSB8020`となり、実機のVS2026 MSBuild Platform Toolset配置を確認した。

確認結果:

```text
VC\Tools\MSVC\14.44.35207             present
MSBuild ... Win32\PlatformToolsets\v145  present
MSBuild ... x64\PlatformToolsets\v145    present
MSBuild ... PlatformToolsets\v143          not present
```

このためBM-003の指定を修正し、MSBuild統合とCompiler Versionを分離する。

```text
PlatformToolset = v145
VCToolsVersion  = 14.44.35207
```

`v145`はProject/MSBuild統合の選択であり、PoC 1のCompilerを最新Versionへ変更する意味ではない。Compiler本体は`VCToolsVersion`で14.44.35207へ固定する。


BM-003ではSource Codeを変更せず、Build定義のみを最小限Retargetする。

適用内容:

```text
ToolsVersion                15.0 -> Current
PlatformToolset             v120 / v120_xp -> v145
VCToolsVersion              14.44.35207
WindowsTargetPlatformVersion 10.0.26100.0
WTL Include                 Machine local path -> build/dependencies.props
```

対象は既存Project Configuration全体のToolset参照であるが、PoC 1で実際にBuildするConfigurationはSolutionに存在する次の2つだけとする。

```text
Debug|Win32
Release|Win32
```

`Release-X64|Win32`はProject内部にHistorical Evidenceとして残す。Platformは依然`Win32`であり、BM-003ではx64 Configurationへ変換しない。

旧`IncludePath`に存在した、

```text
C:\Dev\vc2013\WTL90_4140_Final\Include
```

は削除し、Standard VC / Windows SDK Include PathはMSBuild Toolchainへ任せる。WTLだけを`AdditionalIncludeDirectories`としてRepository-managed Property Sheetから追加する。

Dependency未Restore時は`build/dependencies.props`がBuild開始前に停止し、暗黙Downloadは行わない。

Build Helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-poc-x86.ps1 -Configuration Debug
```

このBuildで生じるErrorをBM-004 Compile Blocker Inventoryの入力とする。

---

## 16. Initial Build Gate

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

## 17. Proposed Change Sequence

```text
BM-001  COMPLETE
Add build documentation / .vsconfig / environment verification

BM-002  COMPLETE
Add hash-pinned WTL 9.1.5321 / 9.0.4140 restore
and verify repository-managed dependency paths

BM-003  COMPLETE
Retarget project to PlatformToolset v145 / MSVC 14.44 / SDK 26100
and replace the machine-local WTL include path

BM-004  IN PROGRESS
Fix compile blockers only and record them in compile-blockers.md

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

## 18. User Preparation

Repository Rootに`.vsconfig`と`development-environment.md`を追加したため、PoC 1の開発環境準備Gateは成立した。

User側ではこの時点からVisual Studio Community 2026 Stableを導入し、`.vsconfig`をImportしてよい。

旧Visual Studio、v120、v120_xp、WTLを任意Local Pathへ手作業で追加導入しない。

Visual Studio Environment GateとWTL Restoreを含むBM-002 Gateは実機で通過済みである。

BM-003適用後は`tools/build-poc-x86.ps1`から`Debug|Win32`を最初にBuildし、失敗した場合は出力を変更せずBM-004のBlocker Inventoryとして扱う。

---

## 19. Open Items

- Windows SDK 26100 familyのServicing Build差異がBuildへ与える影響
- Minimum supported Windows Version
- WTL 9.1.5321 Primaryと9.0.4140 Compatibility ProfileのCompile / Behavior差分
- WTL 10.1.0へのUpgrade時期
- `/MT`継続か`/MD`移行か
- Warning Levelの最終値
- Spectre / CFG / CET等のRelease既定
- Historical `Release-X64|Win32`の意図と廃止時期
- CI Build環境

これらはPoC 1開始前または該当Phase直前に確定する。

## 20. BM-004 First Compile Result

BM-003適用後の実機`Debug|Win32` BuildはMSBuild / PlatformToolset / MSVC / SDK / ATL / WTLを通過し、`stdafx.cpp`のCompiler実行まで到達した。これによりBM-003 Retarget GateはPassとする。

最初のBlockerはMSVC 14.44で`<hash_map>`がDeprecation ErrorとなるC1189である。

PoC 1ではBehavior差を避けるため、直ちに`std::unordered_map`へ置換せず、`build/legacy-compat.props`に`_SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS`を隔離してBaseline Compileを継続する。

詳細と恒久対応方針は[Compile Blocker Inventory](compile-blockers.md)を参照する。

同時に確認された`/Gm` D9035はBuild Blockerではないため、このStepではProject Settingを変更せずInventoryへ記録する。



## 21. BM-004 Second Compile Result

CB-001 mitigation後の実機`Debug|Win32` Buildでは、`<hash_map>` C1189を通過し、多数のTranslation UnitのCompileへ進んだ。

新たなBlockerは2系統である。

1. `Utilities/PtrCollection.h`の`(T*)& operator[]`がModern MSVCで標準C++宣言としてParseされない。
2. `ArchiverCode/arc_interface.cpp`で`CA2T(szBuffer)` temporaryを`TRACE`の可変個引数へ直接渡しており、ATL conversion classの非標準varargs passingとして拒否される。

PoC 1ではそれぞれ、意図されていた`T*&`戻り値を標準構文で明示し、ATL conversion結果は`CString`へmaterializeしてから`GetString()`を`TRACE`へ渡す最小修正とする。

同時に`FileOperation.cpp`の`[[nodiscard]]`戻り値破棄Warning C4834を確認した。これはcorrectnessに関係する可能性があるため抑制せず、Baseline Build成立後の個別Audit対象としてInventoryへ残す。
