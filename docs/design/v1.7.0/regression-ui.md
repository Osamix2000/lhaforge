# PoC 2-A UI / Configuration Read Regression

- Status: Ready for manual comparison
- Scope: Original v1.6.7 vs Modern x86
- Safety level: read-only UI pass first
- External configuration writes: must remain unchanged

Related:

- [Regression Baseline](regression-baseline.md)
- [PoC Plan](poc-plan.md)
- [Legacy Baseline](../../legacy/v1.6.7/legacy-baseline.md)

---

## 1. Why a Sandbox Is Required

v1.6.7の設定解決は単純な`/cfg`だけでは完全隔離にならない。

`CConfigManager`は起動時にまずModule Directoryの`LFCaldix.ini`を確認し、存在しなければCommon AppData側を使用する。また`LhaForge.ini`もModule Directoryを最優先するが、存在しなければCommon AppData / AppDataへFallbackする。

そのためPoC 2ではOriginal/ModernのEXEを別のSandboxへCopyし、それぞれのEXE横に次を配置する。

```text
LhaForge.exe
LhaForge.ini
LFCaldix.ini
dll\
Launch.cmd
```

これにより起動直後のDefault Path解決からSandbox内へ固定する。

`/cfg:<sandbox>\LhaForge.ini`も併用し、Command Line解釈後のConfig Pathも明示する。

---

## 2. Update Suppression

Sandboxの`LhaForge.ini`は次を含む。

```ini
[Update]
SilentUpdate=0
AskUpdate=0
Interval=21
```

v1.6.7では`AskUpdate=false`ならArchiver DLL Update確認を行わない。

PoC 2-AではLFCaldix起動やDLL UpdateをRegression対象に含めない。

---

## 3. Prepare

Modern Release Buildを標準比較対象とする。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-ui-regression.ps1 -OriginalExe "C:\path\to\official-v1.6.7\LhaForge.exe"
```

既存Sandboxを作り直す場合:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-ui-regression.ps1 -OriginalExe "C:\path\to\official-v1.6.7\LhaForge.exe" -Force
```

Scriptは:

1. Modern `Release|Win32`をBuild
2. Original / Modern Binaryがx86 PEであることを確認
3. `.baseline\poc2-ui\original`を作成
4. `.baseline\poc2-ui\modern`を作成
5. Local `LhaForge.ini` / `LFCaldix.ini`を配置
6. External AppData / ProgramData stateをSnapshot
7. Local `CHECKLIST.md`を生成

する。

---

## 4. First Pass Rules

最初のUI比較では:

- Original/ModernともSandboxの`Launch.cmd`だけを実行する
- Association変更を行わない
- Shell Extension変更を行わない
- DLL Updateを実行しない
- Config Dialogは**Cancelで閉じる**
- 最初は設定を書き込まない

このPassの目的はWindow/Page/Controlの表示とStartup/Shutdown挙動の比較だけ。

---

## 5. Verify Isolation

両方をCancelで閉じた後:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-poc2-ui-isolation.ps1
```

確認対象:

```text
%APPDATA%\LhaForge
%APPDATA%\LhaForge\LhaForge.ini
%ProgramData%\LhaForge
%ProgramData%\LhaForge\LhaForge.ini
%ProgramData%\LhaForge\LFCaldix.ini
```

Prepare前から存在したPathはContent / timestampを含めて変更されていないことを確認する。

Local Evidence:

```text
.baseline\poc2-ui\external-state-before.json
.baseline\poc2-ui\isolation-report.json
.baseline\poc2-ui\CHECKLIST.md
```

`.baseline`はGit管理しない。

---

## 6. Pass Criteria

PoC 2-A first pass:

- Original x86 binary staged
- Modern x86 binary staged
- both launch without immediate crash
- configuration dialog appears
- main configuration pages are viewable
- obvious clipping / layout regressionなし
- Cancel shutdown succeeds
- external AppData / ProgramData state unchanged

差が見つかった場合:

```text
MATCH
EXPECTED_DIFFERENCE
REGRESSION
SECURITY_CHANGE_REQUIRED
UNKNOWN
```

で分類する。

---

## 7. Next Step

First passとIsolation VerificationがPassした後、PoC 2-A second passとしてSandbox内だけでConfig Save / Reloadを比較する。

Association / Shell / LFCaldix / External DLL操作はsecond passにも含めず、後続Layerへ分離する。
