# LhaForge v1.7.0 Development Environment

- Status: Ready for PoC 1 setup
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Development branch: `develop-v1.7.0`
- Tooling evidence snapshot: 2026-07-29
- Purpose: PoC 1「Reproducible Modern x86 Build」を開始するための標準開発環境を定義する。

Related documents:

- `build-modernization.md`
- `poc-plan.md`
- `design-review.md`
- `risk-register.md`
- `encoding.md`
- `security.md`

---

## 1. Scope

このDocumentは、v1.7.xのPrimary Development Environmentを再現可能にするための導入仕様である。

最初の目的は、

> Visual Studio 2026上で、v1.6.7 Main ApplicationをModern Toolchainへ段階的にRetargetし、x86のRegression Baselineを作る

ことである。

この時点では次を行わない。

- x64化
- WTL 10.xへの更新
- UI Modernization
- Built-in Backend実装
- Installer実装
- Minimum Windows Versionの最終決定
- Security Mitigationの一括有効化

---

## 2. Standard IDE

標準IDEは、

```text
Visual Studio Community 2026
Stable channel
```

とする。

Community Editionを標準とする理由:

- 個人開発およびOpen Source開発で利用可能
- Visual Studio 2026のC++ / MSBuild / Debuggerを利用可能
- `.vsconfig`によって必要ComponentをRepositoryから指定できる
- Build ToolsのみのCI環境へ後から展開しやすい

Professional / Enterpriseを使用してもよいが、LhaForge Buildがそれら固有機能へ依存してはならない。

Preview / InsidersはPrimary Build Environmentに使用しない。

---

## 3. Repository `.vsconfig`

Repository Rootの、

```text
.vsconfig
```

を標準Installation Configurationとする。

PoC 1開始時点のComponentは次のとおり。

```text
Microsoft.VisualStudio.Workload.NativeDesktop
Microsoft.VisualStudio.ComponentGroup.VC.Tools.143.x86.x64
Microsoft.VisualStudio.Component.VC.14.44.17.14.ATL
Microsoft.VisualStudio.Component.Windows11SDK.26100
Microsoft.VisualStudio.Component.NuGet
```

### 3.1 Desktop development with C++

```text
Microsoft.VisualStudio.Workload.NativeDesktop
```

MSBuild、C++ IDE、Debugger等の基本Desktop Development環境を提供する。

### 3.2 Baseline MSVC

PoC 1では、

```text
v143
MSVC 14.44 family
x86 / x64 Build Tools
```

をBaseline Toolsetとする。

Visual Studio 2026にはより新しいMSVCも存在するが、最初のBuildでCompiler差分を増やさないため、VS2022最終世代のv143 / 14.44を意図的に利用する。

x64 Build Toolsも導入するが、PoC 1のTargetはWin32である。

x64 Toolは後続PoCで同一環境を利用するため先に導入する。

### 3.3 ATL

WTLはATLを基盤とするため、

```text
Microsoft.VisualStudio.Component.VC.14.44.17.14.ATL
```

を明示的に要求する。

MFCは現行`LhaForge.vcxproj`で`UseOfMfc=false`であり、PoC 1の必須Componentにはしない。

### 3.4 Windows SDK

```text
Microsoft.VisualStudio.Component.Windows11SDK.26100
```

をBaseline SDK Componentとする。

Projectで最初に評価するTarget Platform Versionは、

```text
10.0.26100.0
```

とする。

SDKのServicing BuildとTarget Platform Versionの概念は分離する。

Minimum Runtime OSはこのSDK Versionから自動決定しない。

### 3.5 NuGet

WTL 9.0.4140を再現可能なDependencyとして取得する候補としてNuGetを利用できるよう、NuGet Componentを明示する。

ただしPoC 1のDependency Restore方式はBM-002で確定する。

DeveloperがWTLを手作業で`C:\Dev\...`へ配置する方式には戻さない。

---

## 4. Why v143 Instead of Latest MSVC

Visual Studio 2026の導入と同時に最新Compilerへ直接移行すると、

```text
VS2013 → VS2026
v120   → latest MSVC
old SDK → current SDK
```

が同じChange Setになる。

この状態ではCompile / Runtime差異が発生した際に原因を分離しにくい。

そこで最初は、

```text
Visual Studio 2026 IDE
        +
v143 / MSVC 14.44
        +
Windows SDK 26100
        +
WTL 9.0.4140
```

をBaseline候補とする。

Modern x86 Regression成立後、最新MSVCへの更新は別Commit / 別Regressionとして評価する。

---

## 5. WTL Policy

最初のBuildではHistorical Dependencyに合わせ、

```text
WTL 9.0.4140
```

を使用する。

SourceForgeのWTL 9.0.4140 Final配布物にはSHA-256が公開されているため、Dependency Bootstrapを実装する場合はHash検証を必須とする。

RepositoryへWTLを直接Vendorするか、NuGet / Official archiveからRestoreするかはBM-002で決定する。

この段階ではUserがWTLを別途Installする必要はない。

WTL 10.1.0への更新はRegression Baseline成立後に独立して評価する。

---

## 6. Installation Procedure

### 6.1 Visual Studio未導入の場合

1. Microsoft公式からVisual Studio Community 2026 StableをInstallする。
2. Visual Studio InstallerでRepository Rootの`.vsconfig`をImportする。
3. 表示されるComponent内容を確認してInstallする。
4. Preview / Insiders Componentを追加しない。
5. VS2013、v120、v120_xpを追加Installしない。
6. WTLを手作業で配置しない。

`.vsconfig`はSolution Rootへ置かれているため、Visual Studioが不足Componentを検出した場合にもInstallを案内できる。

### 6.2 Visual Studio 2026が既にある場合

Visual Studio Installerから、

```text
More
→ Import configuration
→ .vsconfig
```

を選択し、不足Componentを追加する。

既存の他Workloadを削除する必要はない。

---

## 7. What the User Should Not Prepare Manually

PoC 1開始前に、次を自己判断でInstall / Copyしない。

```text
Visual Studio 2013
v120 / v120_xp Toolset
古いWindows SDK
WTL 9.0の任意Local Copy
ATL / MFCの別配布物
外部Archive DLLの開発SDK
```

必要になったHistorical Toolchainは、Primary Development Environmentへ混在させずDisposable VM等で別途検証する。

---

## 8. Verification

Visual Studio導入後は、Repositoryの、

```text
tools/verify-vs-environment.ps1
```

でPoC 1に必要なVisual Studio ComponentとSDKを確認できる。

PowerShellからRepository Rootで、

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-vs-environment.ps1
```

を実行する。

このScriptはWindows PowerShell 5.1 (`powershell.exe`) でも確実に解釈できるよう、Repository上ではASCII-onlyで管理する。Windows PowerShell 5.1はUTF-8 BOMなしのNon-ASCII Scriptを正しく判定できないため、日本語Message等を直接埋め込まない。

成功時はExit Code `0`、不足がある場合は非0とする。

Verification ScriptはBuildを行わない。

WTLはBM-002でRepository-managed Dependency Restoreを実装した後にVerification対象へ追加する。

---

## 9. First Build Boundary

Visual StudioをInstallしただけでは、現行Projectはそのまま正常Buildできることを期待しない。

現状は、

```text
PlatformToolset = v120 / v120_xp
WTL Include = C:\Dev\vc2013\WTL90_4140_Final\Include
```

というHistorical設定を持つ。

最初の実Buildは次のChangeを段階的に行ってから実施する。

```text
BM-002 WTL Restore
BM-003 v143 / SDK Retarget
BM-004 Compile blocker fix
```

Visual StudioがSolutionを開いた際に自動Retargetを提案しても、内容を確認せず一括適用しない。

Project File変更はGit差分として管理する。

---

## 10. Version Pinning Policy

固定するもの:

```text
Baseline compiler family = v143 / 14.44
Baseline SDK family      = 26100
Baseline WTL             = 9.0.4140
```

固定しないもの:

```text
Visual Studio 2026 IDE servicing patch
Windows SDK servicing package patch
```

IDEのSecurity / Bug Fix Updateを阻害しないため、Visual Studio本体のPatch Levelは固定しない。

SDK Servicing UpdateでBehavior Differenceが発生した場合は、Build Logへ実Versionを記録し、必要に応じて再現用Versionを追加固定する。

---

## 11. Environment Evidence

PoC Buildを実施する際は最低限、次を記録する。

```text
Visual Studio product version
MSVC toolset version
PlatformToolset
Windows SDK target version
Windows SDK installed servicing build
WTL version
Configuration / Platform
Git commit
```

最初は手動記録でもよいが、後にBuild Script / CIから自動生成する。

---

## 12. CI Direction

PoC 1成立後は、同じBuild PrerequisiteをVisual Studio Build Tools 2026へ展開する。

Developer EnvironmentとCIで、

```text
Compiler family
SDK family
WTL dependency
MSBuild project
```

を共有し、IDEの有無だけを差分とする。

CI導入はModern x86 BuildがLocalで成立してから行う。

---

## 13. Exit Criteria for Environment Setup

PoC 1 Build作業へ進む前に、次を満たす。

1. Visual Studio Community 2026 Stableが導入済み。
2. `.vsconfig`のRequired Componentが導入済み。
3. v143 x86 / x64 Toolsetを利用可能。
4. ATL v14.44を利用可能。
5. Windows SDK 26100 familyを利用可能。
6. `tools/verify-vs-environment.ps1`が成功する。
7. WTL、v120、VS2013を手動追加していない。
8. Repositoryに意図しないProject Retarget差分が発生していない。

このGate成立後、BM-002へ進む。

---

## 14. References

- Microsoft Visual Studio 2026 release notes
  - https://learn.microsoft.com/visualstudio/releases/2026/release-notes
- Visual Studio workload and component IDs
  - https://learn.microsoft.com/visualstudio/install/workload-component-id-vs-professional
- Import or export installation configurations
  - https://learn.microsoft.com/visualstudio/install/import-export-installation-configurations
- Windows SDK versioning overview
  - https://learn.microsoft.com/windows/apps/get-started/versioning-overview
- WTL NuGet package
  - https://www.nuget.org/packages/wtl/
- WTL SourceForge archive
  - https://sourceforge.net/projects/wtl/files/

### Windows PowerShell 5.1 and native UTF-8 JSON

`powershell.exe` (Windows PowerShell 5.1) からnative processのUTF-8 JSONを直接Pipelineで`ConvertFrom-Json`へ渡す実装は避ける。localized stringを含む出力がactive code pageで誤Decodeされ、JSON自体が破損する場合がある。

Environment verifierでは`vswhere -format json -utf8 | ConvertFrom-Json`を使用せず、必要な`-property`を個別に取得する。JSONが必要な場合はbyte-levelでEncodingを明示してDecodeするか、PowerShell 7専用処理として分離する。

