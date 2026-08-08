# LhaForge v1.7.0 x86 Regression Baseline

- Status: In progress
- Baseline source: LhaForge v1.6.7 (`ver_1_6_7`)
- Modern build: `develop-v1.7.0`
- Purpose: x64化やDependency Modernizationの前に、Modern Toolchainで再構築したx86版をBehavior比較の基準として固定する。

Related documents:

- `poc-plan.md`
- `build-modernization.md`
- `compile-blockers.md`
- `development-environment.md`
- `dependencies.md`
- `../../legacy/v1.6.7/legacy-baseline.md`

---

## 1. PoC 1 Build Gate Result

2026-07-30の実機確認で次をPassした。

```text
Visual Studio Community 2026 18.8.2
PlatformToolset v145
MSVC 14.44.35207
Windows SDK 10.0.26100.0
WTL 9.1.5321

Debug|Win32
  Build   PASS
  Startup PASS
  Immediate crash: none observed

Release|Win32
  Build   PASS
  Startup PASS
  Immediate crash: none observed
```

生成物:

```text
Debug\LhaForge.exe
Release\LhaForge.exe
```

`Release-X64|Win32`はこのBaselineには含めない。名称に`X64`を含むがHistorical ProjectではWin32 / MachineX86であり、実x64 Configurationではない。

---

## 2. Reproducible Build Evidence

次でDebug / Releaseを再Buildし、生成PEがWin32/x86 (`IMAGE_FILE_MACHINE_I386 = 0x014c`) であることを確認する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-poc-x86-baseline.ps1
```

完全Rebuild:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-poc-x86-baseline.ps1 -Rebuild
```

Scriptは次を確認・記録する。

- Debug|Win32 Build
- Release|Win32 Build
- `LhaForge.exe`のPE Machine
- File size
- SHA-256
- File / Product Version

Local report:

```text
.baseline\poc1-x86-baseline.json
```

`.baseline`はMachine-local EvidenceでありGit管理しない。SHA-256はToolchain / Linker outputの観測値であり、Behavior互換性そのものを意味しない。

---

## 3. Known Build Warnings

Baseline成立時点で、次はBuildを停止しないKnown Warningとして残す。

### BW-001: `/Gm` deprecated

Debugで確認。

```text
warning D9035
```

Historical `MinimalRebuild=true`由来。Baselineを成立させるためだけの変更は行わない。

### BW-002: ignored `[[nodiscard]]`

Releaseでも確認。

```text
FileOperation.cpp(674): warning C4834
FileOperation.cpp(675): warning C4834
```

File Operationのerror handlingに関係する可能性があるため、単純抑制しない。

### BW-003: `/EDITANDCONTINUE` and `/SAFESEH`

Debug Linkで確認。

```text
warning LNK4075: /EDITANDCONTINUE is ignored due to /SAFESEH
```

Buildは成功している。Debug Build settingのModernization時に整理する。

---

## 4. Regression Layers

Regression確認を一度に行わず、次のLayerに分ける。

### Layer A: Build / Startup

Status: **Pass**

- Environment Verification
- Debug Build
- Release Build
- x86 PE Machine
- Debug Startup
- Release Startup
- immediate crashなし
- main window表示

### Layer B: UI / Configuration

Status: **Complete for PoC 2-A (UI read + Config save/reload MATCH)**

確認対象:

- Configuration DialogをOriginal / Modernで比較
- Main Window基本操作
- File List Window
- Menu / Toolbar
- About / Version表示
- Existing configuration read
- Configuration save / reload

Source確認の結果、Module-local `LhaForge.ini` / `LFCaldix.ini`を配置したStaged EXEを使用することで、AppData / ProgramData fallbackを避けられる。PoC 2-A first passでは`AskUpdate=0`の隔離Configを使用し、DialogはCancelで閉じる。

手順は[PoC 2-A UI Regression](regression-ui.md)および[Config Save / Reload Regression](regression-config.md)を参照する。Cancel-only UI / Isolationに加え、Clean Windows VMでConfig Save / Reload比較も完了し、Original / ModernのSemantic INI、`LFCaldix.ini`、外部AppData / ProgramData / Registry状態は`MATCH`またはunchangedとなった。次はPoC 2-BのArchive基本操作Regressionへ進む。

### Layer C: Archive Operations

Status: **Pending**

確認対象:

- Archive list
- Test Archive
- Extract
- Compress
- Japanese filename / path
- CP932 compatibility
- error path

External Archive DLLの有無によって結果が変わるため、使用DLL / Version / Fixtureを固定してから比較する。

### Layer D: Windows Integration

Status: **Pending**

確認対象:

- File Association
- Shell Extension
- Drag & Drop
- LFCaldix entry point
- Update entry point
- MenuEditor / Unregisterとの関係

Registry / Shell変更を伴う項目は、単なる起動Smoke Testと分離する。

---

## 5. Comparison Rule

Modern x86 BuildとOriginal v1.6.7の差を見つけた場合、即座に「Regression」と断定しない。

分類:

```text
MATCH
  観測上同等

EXPECTED_DIFFERENCE
  Toolchain / OS差として意図的または不可避

REGRESSION
  v1.6.7互換として維持すべきBehaviorが変化

SECURITY_CHANGE_REQUIRED
  旧Behaviorは再現すべきでない

UNKNOWN
  追加調査が必要
```

Security問題を「Baselineと同じにする」目的で復元しない。

---

## 6. Exit Criteria for Regression Baseline

PoC 2を完了とする最低条件:

1. Debug / Release x86 Buildを再現できる。
2. 両Binaryがx86 PEであることを自動確認できる。
3. Debug / Release Startupを確認済み。
4. Configuration readの主要経路を確認する。
5. 少なくとも1つの固定Archive FixtureでList / Extract / Compressを比較する。
6. Japanese Path / CP932 Fixtureを確認する。
7. Known Differenceを文書化する。
8. Windows IntegrationのうちPoC 3開始前に必要な範囲を観測する。

PoC 2完了後にActual x64 Main Applicationへ進む。
