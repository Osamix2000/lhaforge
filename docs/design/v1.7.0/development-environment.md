# LhaForge v1.7.0 Development Environment

- Status: Visual Studio environment verified / BM-002 WTL restore ready
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
- `dependencies.md`

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

> Note: `.vsconfig`のComponent ID中の`143`はVisual Studio Installer上のLegacy compiler package group名であり、Projectの`PlatformToolset`指定を意味しない。PoC 1実機ではMSVC 14.44 compilerが導入され、MSBuild Platform Toolset登録はv145である。

### 3.1 Desktop development with C++

```text
Microsoft.VisualStudio.Workload.NativeDesktop
```

MSBuild、C++ IDE、Debugger等の基本Desktop Development環境を提供する。

### 3.2 Baseline MSVC

PoC 1では、

```text
PlatformToolset v145
MSVC 14.44 compiler family
x86 / x64 Build Tools
```

をBaseline Toolsetとする。

Visual Studio 2026にはより新しいMSVCも存在するが、最初のBuildでCompiler差分を増やさないため、Compiler本体はMSVC 14.44へ固定する。一方、MSBuildのPlatform Toolset統合はVS2026に存在するv145を使用する。

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

NuGet ComponentはVisual Studioの標準的なPackage Managementと将来Dependencyの評価に利用できるため導入する。

BM-002のWTL RestoreはNuGet Packageへ依存せず、Official SourceForge Archive + pinned SHA-256方式を採用した。

DeveloperがWTLを手作業で`C:\Dev\...`へ配置する方式には戻さない。

---

## 4. Why MSVC 14.44 Instead of Latest Compiler

Visual Studio 2026の導入と同時に最新Compilerへ直接移行すると、

```text
Solution metadata VS2013 / author environment VS2017 + v120 → VS2026
v120   → latest MSVC
old SDK → current SDK
```

が同じChange Setになる。

この状態ではCompile / Runtime差異が発生した際に原因を分離しにくい。

そこで最初は、

```text
Visual Studio 2026 IDE
        +
PlatformToolset v145
        +
MSVC 14.44
        +
Windows SDK 26100
        +
WTL 9.1.5321 Primary / 9.0.4140 Compatibility
```

をBaseline候補とする。

Modern x86 Regression成立後、最新MSVCへの更新は別Commit / 別Regressionとして評価する。

---

## 5. WTL Policy

公式v1.6.7 Source TreeにはWTL Version Evidenceの食い違いがある。

`source.txt`は`WTL 9.1 Final`を明記する一方、`LhaForge.vcxproj`には`WTL90_4140_Final`という固定Pathが残っている。

BM-002では次の2 ProfileをHash固定でRestore可能にする。

```text
Primary:       WTL 9.1.5321 Final
Compatibility: WTL 9.0.4140 Final
```

PrimaryはAuthorが明示した`source.txt`を優先する。9.0.4140はProject FileのHistorical Path Evidenceを検証する比較用として保持する。

ArchiveはRepositoryへVendorせず、`tools/restore-wtl.ps1`がOfficial SourceForge配布物を取得してSHA-256を検証した後、`.deps\wtl\<version>`へ展開する。Offline Archiveも`-ArchivePath`で利用できる。

詳細は[Dependency Management](dependencies.md)を参照する。

WTL 10.xへの更新はRegression Baseline成立後に独立して評価する。

---

## 6. Installation Procedure

### 6.1 Visual Studio未導入の場合

1. Microsoft公式からVisual Studio Community 2026 StableをInstallする。
2. Visual Studio InstallerでRepository Rootの`.vsconfig`をImportする。
3. 表示されるComponent内容を確認してInstallする。
4. Preview / Insiders Componentを追加しない。
5. VS2013、v120、v120_xpを追加Installしない。
6. WTLを手作業で任意Pathへ配置しない。
7. Visual Studio導入後、`tools/restore-wtl.ps1`でWTLをRepository-managed Restoreする。

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
Visual Studio 2013 / 2017 historical IDE recreation
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

WTLはBM-002でRepository-managed Dependency Restore対象となり、Default ProfileのWTL 9.1.5321がEnvironment Verification対象となる。

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
BM-003 v145 integration / MSVC 14.44 / SDK Retarget
BM-004 Compile blocker fix
```

Visual StudioがSolutionを開いた際に自動Retargetを提案しても、内容を確認せず一括適用しない。

Project File変更はGit差分として管理する。

---

## 10. Version Pinning Policy

固定するもの:

```text
Baseline PlatformToolset  = v145
Baseline compiler family = MSVC 14.44
Baseline SDK family      = 26100
Baseline WTL             = 9.1.5321 Primary / 9.0.4140 Compatibility
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
3. VS2026のPlatformToolset v145をWin32 / x64で利用可能。
4. MSVC 14.44 x86 / x64 compilerを利用可能。
5. ATL v14.44を利用可能。
6. Windows SDK 26100 familyを利用可能。
7. `tools/verify-vs-environment.ps1`が成功する。
8. WTL、v120、Historical Visual Studioを任意Local Pathへ手動追加していない。
9. Repositoryに意図しないProject Retarget差分が発生していない。

Visual Studio / MSVC / SDKのEnvironment Gateは2026-07-29に実機でPassした。
BM-002適用後のWTL 9.1.5321 Restoreを含むEnvironment Gateも実機でPass済みである。

---

## 14. PoC 1 x86 Build Command

BM-003適用後、最初のBuildはVisual Studio UIから手動Retargetせず、RepositoryのBuild Helperを使用する。

Debug:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-poc-x86.ps1 -Configuration Debug
```

Release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-poc-x86.ps1 -Configuration Release
```

Rebuildが必要な場合のみ`-Rebuild`を指定する。

Build Helperは最初に`verify-vs-environment.ps1`を実行し、Environment Gateが通った場合のみ`LhaForge.sln`の`Win32` Buildを開始する。

BM-003時点ではBuild成功を前提としない。Modern Compiler / SDKで露出したErrorはBM-004のCompile Blockerとして分類し、Source変更はBlocker解消に必要な最小範囲へ限定する。

---

## 15. References

- Microsoft Visual Studio 2026 release notes
  - https://learn.microsoft.com/visualstudio/releases/2026/release-notes
- Visual Studio workload and component IDs
  - https://learn.microsoft.com/visualstudio/install/workload-component-id-vs-professional
- Import or export installation configurations
  - https://learn.microsoft.com/visualstudio/install/import-export-installation-configurations
- Windows SDK versioning overview
  - https://learn.microsoft.com/windows/apps/get-started/versioning-overview
- WTL SourceForge archive
  - https://sourceforge.net/projects/wtl/files/

### Windows PowerShell 5.1 and native UTF-8 JSON

`powershell.exe` (Windows PowerShell 5.1) からnative processのUTF-8 JSONを直接Pipelineで`ConvertFrom-Json`へ渡す実装は避ける。localized stringを含む出力がactive code pageで誤Decodeされ、JSON自体が破損する場合がある。

Environment verifierでは`vswhere -format json -utf8 | ConvertFrom-Json`を使用せず、必要な`-property`を個別に取得する。JSONが必要な場合はbyte-levelでEncodingを明示してDecodeするか、PowerShell 7専用処理として分離する。



## 15. VS2026 Platform Toolset Verification

PoC 1実機ではMSVC 14.44の`cl.exe`とATLが存在していても、MSBuildの`PlatformToolsets`には`v145`のみが存在し、`v143`は存在しなかった。

そのためEnvironment GateはCompiler Fileの存在だけでなく、次も確認する。

```text
MSBuild\Microsoft\VC\v180\Platforms\Win32\PlatformToolsets\v145
MSBuild\Microsoft\VC\v180\Platforms\x64\PlatformToolsets\v145
```

PoC 1のBuild Contractは次のように分離する。

```text
MSBuild integration  PlatformToolset v145
Compiler             VCToolsVersion 14.44.35207
ATL                  14.44
SDK                  10.0.26100.0
```

この区別により、VS2026のBuild integrationを利用しながらCompiler世代を14.44へ固定する。
