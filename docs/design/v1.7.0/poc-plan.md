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
- `zste-format.md`
- `archive-result-ui.md`
- `regression-encoding.md`

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

`tools/verify-poc-x86-baseline.ps1`によるDebug / Release BuildとPE Architecture確認はPass済み。

PoC 2-AはComplete。

* Cancel-only UI / Configuration read / Isolation: PASS
* Config Save → Exit → Reload: PASS
* Original / Modern Semantic INI: MATCH
* `LFCaldix.ini`: MATCH
* External AppData / ProgramData: unchanged
* Association / Shell Registry: unchanged

PoC 2-BはComplete。

固定ZIP Fixtureと同一SHA-256のx86 `7-ZIP32.DLL`をOriginal / Modernへ固定配置し、List / Test / Extract / Compress / Re-extractを比較した。最初のModern Listで`0xC0000005` Crashを検出し、WER Dump / PDB / Source archaeologyからGlobal namespaceにある2種類の`struct COMP`によるODR違反を特定した。Comparator typeを固有化する最小修正後、同一条件で全操作を再実行し、最終Classificationは`MATCH`となった。

PoC 2-B開始前のArchitecture checkpointとして、Zstandard / ZSTE方針をADR-0006と`zste-format.md`へ記録した。ZSTE実装自体はPoC 2-Bへ混在させず、Regression Baseline成立後のBuilt-in Backend実装段階で行う。

PoC 2-C Encoding / Path compatibilityへ進み、PoC 2-C1 Direct Unicode Pathは2026-08-13にOriginal / Modern全Case PASS、最終Classification `MATCH`で完了した。PoC 2-C2正常系Baselineも同日にOriginal / Modern 11 / 11 PASS、最終Classification `MATCH`で完了した。2026-08-23にC2 Abnormal 7 Caseを分離実行し、asserted 5 CaseはOriginal / ModernともSource-derived expectationへ一致、odd-length UTF-16LE / BEの2 CaseもBehavior signatureが一致した。Legacyの奇数byte長UTF-16処理は互換要件として保存しないためAbnormal Classificationを`SECURITY_CHANGE_REQUIRED`とし、PoC 2-C2全体をCompleteとする。

PoC 2-Cは次のSub-stageへ分ける。

```text
PoC 2-C1  Direct Unicode Path                                   Complete / MATCH
PoC 2-C2  Response File Encoding / Newline / Abnormal              Complete / Normal MATCH; Abnormal SECURITY_CHANGE_REQUIRED
PoC 2-C3  ZIP Entry Name Metadata / Cross-platform oriented Fixture Planned / Next
PoC 2-C4  Compound Archive                                         Planned
```

主な対象:

- Japanese Filename / Path
- CP932 / Windows-31J
- UTF-8
- CP932で表現不能なUnicode
- Emoji / Supplementary Plane
- Combining Character
- NFC / NFD
- Response File
- CRLF / LF / CR
- Legacy ZIP metadata
- `.DS_Store` / `__MACOSX` / `._*`のBaseline観測
- Compound Archive

PoC 2-Cでは新しいManual Encoding Override、Extraction Preview、Extraction Filter、Archive Result UIをまだProduction実装しない。Original v1.6.7とModern x86の現在Behaviorを先に固定する。

PoC 2-C3 / 2-C4はBaseline continuityのため`7-ZIP32.DLL` 9.22.0.2をHistorical Regression Backendとして継続使用する。C3で作成するDeterministic ZIP Metadata FixtureはBackend-independent Evidenceとして保存し、PoC 4のOfficial `7z.dll` Backendでも再利用する。

詳細:

- [Regression Baseline](regression-baseline.md)
- [PoC 2-A UI Regression](regression-ui.md)
- [PoC 2-A Config Save / Reload Regression](regression-config.md)
- [PoC 2-B Archive Basic Operation Regression](regression-archive.md)
- [PoC 2-C Encoding / Path Regression Plan](regression-encoding.md)
- [PoC 2-C1 Direct Unicode Path Regression Result](regression-encoding-c1.md)
- [PoC 2-C2 Response File Encoding / Newline Regression Result](regression-encoding-c2.md)

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

## 6. PoC 4: Official 7-Zip x64 Backend

目的:

x64 Main Applicationから、7-Zip公式Upstreamの`7z.dll`をLibraryとして直接利用するManaged Backendが成立することを検証する。

`7z.exe`を子Processとして呼び出す方式はこのPoCの対象としない。最初はOfficial 7-Zip Familyに限定する。

開始時に、当時のOfficial Stable CandidateについてVersion、取得元、SHA-256、License / notice、Security / Release Noteを固定する。Library単体の自動更新は行わず、LhaForge Release単位でValidated Versionを更新する。

確認:

- official upstream provenance / license
- PE architecture
- safe absolute-path load
- native API / interface version probe
- list
- test
- extract
- create where PoC scope permits
- password / progress / cancel boundary
- Unicode / filename metadata
- error mapping
- unload / lifetime
- Idle時に未使用`7z.dll`を不要Loadしないこと

Output:

- `Official7ZipBackend` first x64 adapter
- capability probe contract
- pinned Official 7-Zip dependency evidence
- PoC 2-C3 Fixture再利用によるHistorical vs Official behavior comparison

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

Library最終決定はUpstream Firstを原則とし、実測とLicense / Security review後に行う。第三者Forkは公式Upstreamでは要件を満たせない場合だけ例外候補とする。

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

## 11. PoC 9: Logging / Encoding Modernization

目的:

PoC 2-Cで取得したLegacy Original vs Modern x86のEncoding / Path Baselineを前提に、Multi-process化後の新Logging / Filename Decode / Legacy Boundary Architectureが診断性とCompatibilityを維持できることを確認する。

PoC 2-CはLegacy Behavior Regression、PoC 9はModernized Architecture validationとしてScopeを分離する。

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
