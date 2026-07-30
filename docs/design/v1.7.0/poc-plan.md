# LhaForge v1.7.0 PoC Plan

- Status: Draft
- Target: LhaForge v1.7.x
- Development branch: `develop-v1.7.0`
- Purpose: Architectureを一度に実装せず、Riskの高い前提から順に小さなPoCで検証する。

Related documents:

- `design-review.md`
- `risk-register.md`
- `architecture.md`
- `backend.md`
- `security.md`
- `performance.md`
- `migration.md`
- `installer.md`
- `build-modernization.md`
- `development-environment.md`
- `dependencies.md`

---

## 1. Principle

PoCは新機能を完成させるためではなく、

> 実装方針を決める前提が本当に成立するか

を確認するために行う。

各PoCは可能な限り小さくし、成功 / 失敗の双方をDocumentationへ残す。

PoCで失敗した設計案も削除せず、なぜ採用しなかったかをADRまたはReview Noteとして残す。

---

## 2. Gate 0: Design Readiness

User側準備: **不要**

実施内容:

- Source / Project構成調査
- Open Item整理
- Risk整理
- Dependency候補整理
- Test case整理

Output:

- `design-review.md`
- `risk-register.md`
- `build-modernization.md`
- `development-environment.md`
- `dependencies.md`
- 本Document

Exit:

- Build Modernizationに必要な環境を具体的に指定できる。
- Repository Rootに`.vsconfig`が存在する。
- `development-environment.md`に導入手順が存在する。
- `tools/verify-vs-environment.ps1`でPrerequisiteを確認できる。

Status: **Complete**

---

## 3. PoC 1: Reproducible Modern x86 Build

目的:

> v1.6.7 Main Applicationを、現代Toolchain上でまずx86として再現する。

ここではx64化を同時に行わない。

確認項目:

- current Visual Studio / MSVCでProjectをLoadできるか
- WTL dependencyをMachine固有Pathなしで解決できるか
- Resource / Japanese textが壊れないか
- Debug / Release x86 Build
- Startup
- Basic list / extract / compress
- Existing configuration read

重要:

`Release-X64`という旧Configuration名はx64の証拠として扱わない。

Output:

- reproducible x86 build
- `.vsconfig`
- Build prerequisites document
- Build warnings / incompatibility inventory

User側準備:

Repository Rootの`.vsconfig`と`development-environment.md`に従ってVisual Studio Community 2026 Stableを導入する。

BaselineはPlatformToolset v145 + MSVC 14.44 + Windows SDK 26100 familyとする。Visual Studio Environment Gateは実機でPass済みである。

WTLはBM-002の`tools/restore-wtl.ps1`でPrimary 9.1.5321をRestoreする。Project FileのHistorical Pathを検証する必要がある場合のみ9.0.4140 ProfileでもA/B Buildする。

**旧Visual Studio、v120 / v120_xp、旧SDK、WTLを任意Local Pathへ自己判断で追加導入しない。**

WTL Restore後は`tools/verify-vs-environment.ps1`を再実行し、Dependencyを含むEnvironment Gateを確認する。

BM-001 / BM-002 Gateは実機でPass済み。BM-003ではProject FileをPlatformToolset v145へRetargetし、`VCToolsVersion=14.44.35207`、SDK 26100、Repository-managed WTL参照を適用する。

最初のBuild:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-poc-x86.ps1 -Configuration Debug
```

BM-003直後のBuildは実機でCompiler実行まで到達し、BM-003 Retarget GateをPassした。その後のBM-004で`<hash_map>`、旧Pointer declarator、ATL conversion / varargs、WTL Resource HeaderのCompile Blockerを最小修正した。

2026-07-30に実機で次を確認済み:

```text
Debug|Win32   Build PASS
Debug startup PASS

Release|Win32 Build PASS
Release startup PASS
```

Status: **Complete**

Build / startupの詳細Evidenceと次段のBehavior比較は[Regression Baseline](regression-baseline.md)へ引き継ぐ。

---

## 4. PoC 2: v1.6.7 Regression Baseline

目的:

Modern Toolchain化によってBehaviorが変わっていないことを確認する。

対象:

- startup
- config load / save
- file associationの現状観測
- basic ZIP / 7z等
- file list window
- drag & drop
- archive test
- update entry point
- Japanese path
- CP932-related assets

必要に応じてOriginal v1.6.7 Binaryと並行比較する。

Output:

- regression checklist
- known-difference list
- baseline test assets

Status: **In progress**

最初に`tools/verify-poc-x86-baseline.ps1`でDebug / Release BuildとPE Architectureを再確認し、その後User設定・External DLL・Registry変更を分離したBehavior Testへ進む。

詳細は[Regression Baseline](regression-baseline.md)を参照する。

---

## 5. PoC 3: Actual x64 Main Application

目的:

Main Applicationのx64 Buildを成立させ、x86 assumptionを抽出する。

対象:

- pointer / handle cast
- LPARAM / WPARAM
- size_t / DWORD等
- struct layout
- `_USE_32BIT_TIME_T`
- filesystem / archive metadata
- Registry view
- COM / Shell interaction
- DLL loading

Output:

- x64 compile blocker inventory
- x64 runtime blocker inventory
- actual `x64` Project Configuration

---

## 6. PoC 4: External x64 Backend

目的:

x64 Main ApplicationからExternal x64 Archive DLLを安全に利用できることを検証する。

最初は1 Familyに限定する。

確認:

- discovery
- PE architecture
- absolute-path load
- export / version probe
- list
- extract
- error
- unload / lifetime

Output:

- first x64 adapter
- capability probe contract

---

## 7. PoC 5: LegacyHost x86

目的:

x64 Main Applicationからx86専用DLLを継続利用できることを確認する。

確認:

- Named Pipe connection
- protocol version
- request / response framing
- list / extract
- progress
- cancellation
- timeout
- malformed message rejection
- host crash
- restart / quarantine

大量Archive MetadataはBatch化してIPC round tripを抑える。

---

## 8. PoC 6: Exact Input Set / Compression Exclusion

目的:

Backendによらず、LhaForgeが確定したInputだけをArchiveへ格納できることを確認する。

Test tree例:

```text
project\
├─ src\
├─ .git\
├─ .env
├─ .env.example
└─ README.md
```

確認:

- exclude disabled
- auto exclude
- ask before compress
- custom rule
- nested directory
- symlink / reparse scenario
- External Backend
- Built-in Backend

Acceptance:

除外対象がBackend側の再走査によって混入しない。

---

## 9. PoC 7: Built-in Backend

目的:

Common Backend Interface上でExternal DLLに依存しないBackendが成立することを確認する。

最初はFormatを絞る。

評価:

- license
- x64
- Unicode
- path security integration
- streaming
- create / extract / list / test
- performance
- maintenance activity

Library最終決定は実測とLicense review後に行う。

---

## 10. PoC 8: Security Boundary

目的:

Security DesignをUnit Levelだけでなく実Filesystem上で検証する。

最低Test:

- `../`
- absolute path
- drive path
- UNC
- device path
- ADS
- reserved names
- trailing dot / space
- reparse point
- extraction destination swap
- huge entry count
- extreme compression ratio
- malformed archive
- malformed Unicode

Performance budgetとSecurity budgetを同時に計測する。

---

## 11. PoC 9: Logging / Encoding

目的:

Multi-process化後も診断性を確保し、Legacy Encodingを壊さないことを確認する。

確認:

- Operation / Correlation ID
- LhaForge ↔ LegacyHost trace
- bounded queue
- log sink failure
- CP932 config
- UTF-8 config candidate
- `cldx\読んでね.txt`
- Japanese / supplementary Unicode path
- lossy conversion rejection

---

## 12. PoC 10: Installer / Migration / Recovery

目的:

実データを壊さずv1.6.7 → v1.7.0 Lifecycleを成立させる。

推奨VM Snapshot:

```text
A Clean Windows
B v1.6.7 installed
C first run
D external DLL downloaded / configured
E customized environment
F migration in progress
G v1.7.0 migrated
H uninstall
```

確認:

- custom install path
- Program Files (x86)
- user-modified DLL
- unknown file
- `cldx`
- config
- shell registration
- forced failure
- power-loss-like interruption
- rollback
- repair
- uninstall default preserve
- explicit cleanup

---

## 13. PoC 11: UI / DPI / Shell

目的:

内部Architecture安定後に、v1操作性を維持したModern Windows UIを検証する。

確認:

- native non-client frame
- Common Controls v6
- PerMonitorV2
- Japanese UI font metrics
- layout resizing
- shell context integration
- MenuEditor

Dark modeはこのPoCの必須条件としない。

---

## 14. User Preparation Timeline

現時点:

```text
Design Review / Source Analysis
→ User preparation unnecessary
```

Build PoC開始時:

```text
ChatGPT側で
Visual Studio version
Workload
Components
Windows SDK
WTL dependency
.vsconfig
を確定
        ↓
Userがその内容だけ導入
```

Installer / Migration PoC前:

```text
Disposable Windows VM
Snapshot使用可能な環境
```

を推奨する。

VMは今すぐ必須ではない。

---

## 15. PoC Completion Policy

PoCごとに次を残す。

- Hypothesis
- Environment
- Steps
- Result
- Performance observation
- Security observation
- Compatibility observation
- Decision
- Follow-up

成功したCodeをそのままProduction実装へ昇格させる必要はない。

PoC Codeは品質より検証目的を優先し、本実装へ統合する場合はReviewする。
