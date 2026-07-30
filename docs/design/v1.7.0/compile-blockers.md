# LhaForge v1.7.0 Compile Blocker Inventory

- Status: PoC 1 complete / retained as historical inventory
- Target: PoC 1 / Modern x86 Build
- Baseline: LhaForge v1.6.7
- Toolchain: Visual Studio Community 2026 / PlatformToolset v145 / MSVC 14.44 / Windows SDK 26100 / WTL 9.1.5321
- Purpose: 現代Toolchainでv1.6.7相当のWin32 Buildを成立させる際に発生したCompile / Link Blockerを、回避理由と将来の恒久対応を含めて記録する。

## 1. Rules

PoC 1では、次の原則でBlockerを処理する。

1. まず旧挙動を再現できるx86 Baselineを成立させる。
2. 新機能実装をBlocker回避に混入させない。
3. 挙動差を生み得るModernizationはBaseline成立後の別変更にする。
4. 一時Compatibility Switchは専用Property Sheetへ隔離する。
5. Security / correctness問題は単なるWarning抑制で隠さない。
6. 各Blockerは発生したCompiler Errorを記録し、解消後も履歴を残す。

---

## 2. CB-001: `stdext` hash container deprecation

### Status

Mitigation verified / passed next compile

### First observed

`Debug|Win32`のBM-003初回Compile。

### Compiler output

```text
error C1189: <hash_map> is deprecated and will be REMOVED.
Please use <unordered_map>.
You can define _SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS to suppress this error.
```

### Existing v1.6.7 usage

現在のSourceでは、少なくとも次のLegacy Containerを使用している。

```text
stdafx.h
  <hash_map>
  <hash_set>

FileListWindow/ShellDataManager.*
  std::hash_map

ArchiverCode/ArcEntryInfo.h
  std::hash_map
```

### Decision for PoC 1

PoC 1では`std::hash_map` / `stdext`系Containerを直ちに`std::unordered_map`へ置換しない。

Container置換は、Hash implementation、Iteration order、Bucket behavior、Performance characteristic等の差を持ち込む可能性があり、v1.6.7相当Behaviorを確認する最初のBaseline Buildと同時に行う変更としては大きすぎるためである。

MSVC 14.44が提供するCompatibility Switch:

```text
_SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS
```

のみを`build/legacy-compat.props`から有効化し、Source Codeは変更しない。

### Long-term action

Baseline Regression成立後、Legacy Containerの使用箇所を個別に調査してModern C++ ContainerへのMigrationを別Commitで行う。

その際は最低限、以下を確認する。

- Key comparison / hash behavior
- Iteration orderへ暗黙依存していないか
- Pointer ownership
- Lifetime / invalidation behavior
- Performance regression
- x64 portability

このCompatibility Switchは恒久仕様ではない。

次回Buildでは`stdafx.cpp`を通過し、Project全体のCompileが継続したため、PoC 1のCompatibility mitigationとして有効であることを確認した。

---

## 3. CB-002: `CSmartPtrCollectionArray::operator[]` legacy declarator syntax

### Status

Verified / passed next compile

### First observed

CB-001 mitigation後の`Debug|Win32` Build。

### Compiler output

```text
PtrCollection.h(86): error C2143
PtrCollection.h(86): error C4430
PtrCollection.h(86): error C2059
PtrCollection.h(86): error C2334
```

### Existing source

```cpp
(T*)& operator[](size_t idx){return m_Array[idx];}
```

Modern MSVCではこの宣言を標準的な戻り値型としてParseできない。`m_Array`は`std::vector<T*>`であり、非const `operator[]`の戻り値は`T*&`である。

### Decision for PoC 1

意図されていた戻り値型を変更せず、標準C++の宣言構文へ修正する。

```cpp
T*& operator[](size_t idx){return m_Array[idx];}
```

ContainerやOwnership semanticsは変更しない。これはModernizationではなく、現行Compilerで旧意図を表現するための最小Source compatibility fixとする。

---

## 4. CB-003: ATL conversion temporary passed to variadic `TRACE`

### Status

Verified / passed next compile

### First observed

CB-001 mitigation後の`Debug|Win32` Build。

### Compiler output

```text
arc_interface.cpp(851): error C4839: non-standard use of class ATL::CA2WEX<128> as an argument to a variadic function
arc_interface.cpp(851): error C2248: ATL::CA2WEX<128>::CA2WEX is private
```

### Existing source

```cpp
TRACE(_T("%s\n"),CA2T(szBuffer));
```

`CA2T`はATL conversion objectを生成する。これを`...`の可変個引数へ直接渡す旧記述は、現行MSVCではclass objectのbitwise passingとして拒否される。

### Decision for PoC 1

Conversion結果を`CString`へ一度materializeし、そこから`LPCTSTR`を明示的に取得して`TRACE`へ渡す。

```cpp
CString strTrace;
strTrace=CA2T(szBuffer);
LPCTSTR lpszTrace=strTrace;
TRACE(_T("%s\n"),lpszTrace);
```

Response fileへ書き込むbyte列やEncoding処理自体は変更しない。PoC 1では`TRACE`引数のLifetime / ABI問題だけを修正する。

### Verification history

最初の修正では次の形を試した。

```cpp
CString strTrace(CA2T(szBuffer));
TRACE(_T("%s\n"),strTrace.GetString());
```

この形では実機のMSVC 14.44 Buildで、`GetString`左辺をclassとして扱えない`C2228`が発生した。
そのため、PoC 1ではATL/MFC CString APIの追加呼出しに依存せず、既存の`LPCTSTR`暗黙変換を代入時に明示的に確定する形へ変更した。

次回Buildでは`arc_interface.cpp`が正常にCompileされ、Resource Compilerまで進んだため、第2修正がPoC 1のCompatibility fixとして有効であることを確認した。

---

## 5. CB-004: Resource Compiler cannot locate `atlres.h`

### Status

Verified / Debug and Release builds passed

### First observed

CB-003通過後の`Debug|Win32` Build。

### Compiler output

```text
resource.rc(10): fatal error RC1015: cannot open include file 'atlres.h'
```

### Existing source

`resource.rc`はVisual C++ generated resource scriptとして、ATLのResource定義を使用するため次をIncludeしている。

```cpp
#include "atlres.h"
```

MSVC / ATL本体はEnvironment Verificationで検出済みであり、C++ Compilerは`atlbase.h`および`atlwin.h`を使用できている。一方、Resource Compiler (`rc.exe`) のInclude Search PathはC++ Compilerの`AdditionalIncludeDirectories`とは別設定である。

### Decision for PoC 1

Sourceの`#include "atlres.h"`を変更したり、HeaderをRepositoryへCopyしたりしない。

最初の修正では`atlres.h`をMicrosoft ATL側のHeaderと誤認し、

```text
$(VCToolsInstallDir)atlmfc\include
```

をResource Compilerへ追加した。しかし実機Environment VerificationでMSVC 14.44のATL Includeには`atlres.h`が存在しないことを確認した。

WTL配布物側には`atlres.h`が含まれるため、正しいDependency境界は次の通りとする。

```text
Microsoft ATL:
  atlbase.h
  atlwin.h

WTL:
  atlapp.h
  atlres.h
  ...
```

`build/dependencies.props`の`ResourceCompile`には、

```text
$(LhaForgeWTLInclude)
```

を追加し、Resource CompilerがRestore済みWTL 9.1.5321の`atlres.h`を使用する。

`tools/restore-wtl.ps1`でも`Include\atlres.h`をRequired Headerとして検証し、`verify-vs-environment.ps1`ではATL側ではなくWTL側の`atlres.h`を確認する。

### Long-term action

Resource Headerも通常のWTL Headerと同じVersion-pinned Dependencyとして扱い、固定絶対PathやVisual Studio内部配置へ依存させない。

### Verification

Corrected fix適用後、実機で`Debug|Win32`および`Release|Win32`がResource Compile / Linkを含めて完了した。

---


## 6. BW-001: `/Gm` deprecation warning

### Status

Observed / non-blocking / deferred

### Compiler output

```text
warning D9035: option 'Gm' is deprecated and will be removed in a future version
```

### Source

Historical Debug Configurationの`MinimalRebuild=true`に由来する。

### Decision

現在はBuild BlockerではないためCB-001と同時には変更しない。

最初のx86 Compile / Linkを通した後、Modern Toolchainで不要なBuild-only OptionとしてProject Settingを整理する。

---

## 7. BW-002: ignored `[[nodiscard]]` results

### Status

Observed / non-blocking / deferred

### Compiler output

```text
FileOperation.cpp(674,34): warning C4834
FileOperation.cpp(675,34): warning C4834
```

### Decision

戻り値を無条件に捨ててよいかはFile Operationのcorrectness / error handlingに関係するため、単純なWarning抑制は行わない。Baseline Build成立後に呼出先と旧挙動を確認して個別に修正する。

---

## 8. BW-003: `/EDITANDCONTINUE` ignored with `/SAFESEH`

### Status

Observed / non-blocking / deferred

### Compiler output

Debug Linkで次を確認した。

```text
warning LNK4075: /EDITANDCONTINUE is ignored due to /SAFESEH
```

### Decision

Debug Buildは正常完了しておりPoC 1のBlockerではない。Historical Debug Settingの整理時に、Edit and ContinueとSafeSEHの現在の意図を確認してBuild-only Optionとして整理する。

---

## 9. Current Gate

```text
BM-003 Project Retarget
    PASS
        ↓
BM-004 Compile Blocker Fix
    CB-001 verified
    CB-002 verified
    CB-003 verified
    CB-004 verified
        ↓
BM-005 x86 Build
    Debug|Win32   PASS
    Release|Win32 PASS
    Debug startup PASS
    Release startup PASS
```

PoC 1のModern x86 Build Gateは完了した。

以降のCompiler / Linker Warningは無条件に抑制せず、Regression Baselineまたは該当Modernization Changeで分類する。
