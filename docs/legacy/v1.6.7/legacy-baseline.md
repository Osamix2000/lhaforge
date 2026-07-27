# LhaForge v1.6.7 Legacy Baseline v1

- Status: Draft / investigation baseline
- Target: LhaForge v1.6.7 final v1.x environment
- Purpose: Preserve the original v1.x design and behavior as evidence before designing LhaForge v1.7.0.
- Policy: Do not treat undocumented behavior as disposable. Record what existed, why it likely existed, and how certain the evidence is before deciding to retain, modernize, migrate, or retire it.

## 1. Scope

This baseline covers the v1.x product family as a set of components rather than only `LhaForge.exe`.

- LhaForge main application
- MenuEditor
- Shell Extension (x86/x64)
- LFAssistant (x86/x64)
- LFCaldix
- Unregister
- EXEpress uninstaller (`epuninst.exe`)
- bundled support files (`lficons.dll`, `b2e32.dll`, help/readme)
- external Integrated Archiver DLL ecosystem
- generated configuration and package/documentation storage (`LhaForge.ini`, `LFCaldix.ini`, `cldx\`)

## 2. Evidence set

### Primary evidence

1. Clean-install snapshot of LhaForge v1.6.7 (`LhaForge.zip`).
2. Snapshot after LFCaldix DLL download (`cldx.zip`).
3. LhaForge v1.6.7 source (`ver_1_6_7` GitHub branch / official v1 source lineage).
4. LFAssistant 1.6.0 source.
5. Shell Extension + MenuEditor 1.6.2 source.
6. LFCaldix 1.22.01 source.
7. Unregister 1.4.0 source.
8. Official legacy LhaForge page and security notices.

### Historical comparison evidence

- LFAssistant 1.5.0
- LFCaldix 1.19.04 / 1.19.07 / 1.21.03 / 1.21.04
- LhaForge 1.4.0 / 1.4.1 source archives
- Shell Extension 1.4.0 / 1.5.0 / 1.6.0

Historical versions are comparison material, not the normative v1.6.7 runtime baseline unless a behavior is confirmed to remain in the final v1.x stack.

## 3. Confidence notation

- **Confirmed**: directly observed in clean runtime data and/or final source.
- **High**: supported by multiple independent pieces of evidence.
- **Medium**: source or runtime evidence exists, but final behavior still requires runtime verification.
- **TBD**: intentionally unresolved; do not build a migration rule around it yet.

## 4. Clean-install filesystem baseline

Immediately after installation, the captured LhaForge directory contains 14 files, all at the installation root:

```text
LhaForge\
├─ LhaForge.exe
├─ MenuEditor.exe
├─ Unregister.exe
├─ epuninst.exe
├─ LFAssist.exe
├─ LFAssist64.exe
├─ LFCaldix.exe
├─ ShellExtDLL.dll
├─ ShellExtDLL64.dll
├─ lficons.dll
├─ b2e32.dll
├─ b2e32.txt
├─ LhaForgeHelp.chm
└─ ReadMe.txt
```

**Confirmed.**

Not present immediately after installation in the supplied clean snapshot:

- `LhaForge.ini`
- `LFCaldix.ini`
- `cldx\`
- typical Integrated Archiver DLLs such as `7-ZIP32.DLL`, `TAR32.DLL`, `UNLHA32.DLL`

This is a key ownership boundary: the installer payload and later runtime/update-generated content are separate concepts.

## 5. Legacy component responsibilities

### 5.1 LhaForge.exe

Primary user-facing archive application.

Known responsibilities include:

- loading and saving LhaForge configuration;
- reading LFCaldix configuration;
- invoking `LFCaldix.exe` for DLL update operations;
- selecting and loading Integrated Archiver DLL implementations;
- archive list/test/extract/create behavior;
- invoking privileged helper behavior indirectly where needed.

**Confirmed / High.**

### 5.2 MenuEditor.exe

User-facing shell-menu editor shipped in the installation root.

It is part of the Shell Extension source family, not a disposable installer helper. The v1.7.0 design should preserve its visible role unless a later decision explicitly replaces the implementation while retaining equivalent UX.

**Confirmed.**

### 5.3 ShellExtDLL.dll / ShellExtDLL64.dll

COM shell extension implementations for 32-bit and 64-bit shell environments.

The 1.6.2 source registers COM class information under `HKEY_CLASSES_ROOT`, installs drag-and-drop/context-menu handler entries, and writes an approved shell-extension value under:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved
```

The x86 and x64 builds use distinct application identities (`LhaForge` / `LhaForge64`).

**Confirmed.**

### 5.4 LFAssist.exe / LFAssist64.exe

Privileged assistant used to perform operations requiring administrator rights, particularly file associations and shell-extension registration.

The 1.6.0 manifest describes it as an assistant for configuring associations and shell extensions and requests `requireAdministrator`.

The helper receives an INI script path and performs requested actions.

#### File associations

LFAssist knows a fixed legacy extension set, including LZH/LHA, ZIP, CAB, 7z, RAR, TAR, gzip, bzip2, ISO, LZMA and XZ families.

When creating an association it uses a ProgID beginning with:

```text
LhaForgeArchive_
```

and points the open command to:

```text
"<LhaForge install dir>\LhaForge.exe" /m "%1"
```

#### Association restoration

Before replacing an existing association, LFAssist can preserve the original file type in the extension key using:

```text
LhaForgeOrgFileType
```

On association removal it restores that previous association if it still exists and only removes the extension key when appropriate.

This is an important legacy safety behavior that should inform v1.7.0 migration/uninstall design.

#### PostProcess/DeleteMe

LFAssist deletes the helper INI only when the INI contains the explicit key phrase:

```ini
[PostProcess]
DeleteMe=Please_Delete_Me
```

This was intentionally designed to avoid accidental deletion from malformed input.

**Confirmed.**

### 5.5 Unregister.exe

`Unregister.exe` is not merely a duplicate file uninstaller. It orchestrates deregistration before handing the installation-directory removal to the EXEpress uninstaller.

Observed flow:

```text
Unregister.exe
    │
    ├─ create temporary INI deregistration script
    │
    ├─ on 64-bit Windows:
    │      LFAssist64.exe <script>
    │      └─ unregister 64-bit shell side
    │
    ├─ mark INI with PostProcess/DeleteMe
    │
    ├─ LFAssist.exe <script>
    │      ├─ remove requested file associations
    │      ├─ unregister 32-bit shell side
    │      └─ delete temporary INI
    │
    └─ epuninst.exe /s
           └─ installer/uninstaller-owned file removal
```

The Unregister source also rewrites the installed `UninstallString` under the LhaForge uninstall registry key to point at its own executable during the deregistration flow.

This strongly suggests a responsibility split:

- `Unregister.exe`: LhaForge-specific state cleanup/orchestration.
- `LFAssist*`: elevated registration changes.
- `epuninst.exe`: installer-owned removal engine.

**Confirmed.**

### 5.6 LFCaldix.exe

LFCaldix is the legacy DLL acquisition/update subsystem based on Caldix and modified for LhaForge.

Known responsibilities include:

- download/update decision logic;
- archive download and extraction;
- DLL installation/replacement;
- delayed replacement when an in-use file cannot be replaced immediately;
- configuration/state handling;
- preservation of downloaded DLL documentation into `cldx\`.

The final 1.22.01 source contains extraction handlers for LZH, ZIP, CAB and 7z package formats and replacement logic using temporary files and delayed replacement when needed.

**Confirmed / High.**

### 5.7 epuninst.exe

EXEpress-provided uninstall engine generated/placed by the legacy installer.

In the v1.6.7 clean snapshot its timestamp differs from the historical product binaries, consistent with installer-time generation/placement. The Unregister source invokes it using `/s` after LhaForge-specific deregistration.

v1.7.0 should preserve the historical role separation in documentation, even if the EXEpress implementation itself is replaced by the new installer architecture.

**High.**

## 6. Configuration baseline

### 6.1 LhaForge.ini

The v1.6.7 main source names the application configuration `LhaForge.ini`.

The common legacy path-selection model is not simply “INI next to EXE”. It supports common and per-user modes and custom configuration paths.

The Shell Extension 1.6.2 source shows this search priority for LhaForge-managed configuration files:

1. file beside the LhaForge/Shell Extension installation;
2. common application-data `LhaForge` location if that file exists;
3. per-user file under an install-directory username subdirectory if it already exists;
4. otherwise per-user roaming AppData `LhaForge` location.

This behavior was designed partly because Vista-era Program Files permissions made per-user AppData the safe default.

The exact v1.6.7 main-application path resolver must be documented independently before final migration rules are frozen.

**High; exact resolver details still being normalized.**

### 6.2 LFCaldix.ini

The v1.6.7 main application explicitly searches for `LFCaldix.ini` beside `LhaForge.exe`; if absent, it prepares/uses a Common AppData `LhaForge\LFCaldix.ini` path.

LhaForge reads this file and also updates update timestamps in it.

Known logical data includes:

- DLL installation path (`[conf] dll=...`);
- last update time;
- update-related shared state.

Therefore `LFCaldix.ini` is shared compatibility/update state, not merely an opaque LFCaldix-private cache file.

**Confirmed.**

### 6.3 Temporary data

The v1.6.7 main application normally uses the Windows temporary directory. If `TMP` and `TEMP` are unavailable, it creates a fallback temporary directory under roaming AppData:

```text
%AppData%\LhaForge\temp\
```

**Confirmed.**

## 7. cldx baseline

The clean-install snapshot does not contain `cldx\`.

After LFCaldix performs DLL download/update, `cldx\` is generated under the LhaForge installation directory in the supplied runtime snapshot.

The supplied `cldx` tree contains per-DLL directories with documentation, headers, import libraries, source archives and other package material. It is not simply the runtime directory from which LhaForge loads all Integrated Archiver DLLs.

The legacy Japanese `読んでね.txt` explicitly states that this directory stores documentation for DLLs downloaded by LFCaldix and asks the user to read those documents.

Therefore the baseline role is:

```text
cldx\ = LFCaldix-managed downloaded-package documentation/support storage
```

It may also contain package-derived binaries for some DLL packages, so v1.7.0 must not assume every file inside is disposable cache.

**Confirmed / High.**

### Encoding note

`読んでね.txt` is CP932/Shift_JIS-era text. The archived filename itself can also be mis-decoded by modern ZIP tooling when legacy filename encoding is not interpreted correctly.

This is useful as a real regression fixture for v1.7.0 legacy-encoding tests.

## 8. External Integrated Archiver DLL baseline

Legacy v1.x architecture treats Integrated Archiver DLLs as external runtime providers.

Examples include 7-ZIP32, TAR32, UNLHA32 and many historical format DLLs.

Important distinctions:

- these DLLs are not all part of the clean installer payload;
- LFCaldix can acquire/update them independently;
- advanced users historically could replace DLLs independently of the LhaForge executable;
- bundled components such as `b2e32.dll` must not automatically be classified the same way merely because they have a `.dll` suffix.

The final runtime location and LFCaldix installation rules for every DLL family are being recorded separately in the DLL matrix.

**High; per-DLL matrix TBD.**

## 9. Legacy DLL loading/security baseline

v1.6.7 already contains security mitigation for DLL loading. Before `LoadLibrary`, its archive interface moves the current directory to the LhaForge module directory to mitigate unsafe DLL search behavior.

Therefore v1.7.0 documentation must not claim that v1.6.7 had no DLL-load protection.

Modernization direction:

- preserve the intent;
- replace implicit current-directory safety assumptions with explicit absolute DLL paths and modern restricted DLL search policy;
- validate architecture, exports/API version and capabilities before selecting a backend.

## 10. Association and shell-registration ownership

Legacy behavior indicates that association/shell state is **application-owned registration state**, while its implementation was delegated to privileged assistants.

The important property is not which EXE happens to modify the Registry, but which component owns the semantic state.

Provisional ownership:

- file associations: LhaForge application state, modified by LFAssist;
- shell COM registration: Shell Extension state, registered/unregistered through LFAssist;
- installer uninstall registration: installer state, with Unregister participating in handoff;
- previous third-party file association: external/user state that LhaForge must restore rather than destroy where possible.

## 11. Provisional ownership model for v1.6.7 evidence

| Item | Legacy creator/manager | Legacy class | v1.7.0 provisional ownership | Confidence |
|---|---|---|---|---|
| `LhaForge.exe` | Installer | Installer payload | Managed | Confirmed |
| `MenuEditor.exe` | Installer / Shell package | User-facing payload | Managed, user-facing | Confirmed |
| `Unregister.exe` | Installer | Deregistration orchestrator | Managed, user-facing legacy role | Confirmed |
| `epuninst.exe` | Installer engine | Installer-generated/managed | Legacy installer component | High |
| `LFAssist.exe` | Installer | Privileged helper | Managed runtime helper | Confirmed |
| `LFAssist64.exe` | Installer | Privileged x64 helper | Managed runtime helper | Confirmed |
| `LFCaldix.exe` | Installer | DLL manager | Managed compatibility component | Confirmed |
| `ShellExtDLL.dll` | Installer | x86 shell extension | Managed runtime shell component | Confirmed |
| `ShellExtDLL64.dll` | Installer | x64 shell extension | Managed runtime shell component | Confirmed |
| `lficons.dll` | Installer | Icon/resource payload | Managed resource | Confirmed |
| `b2e32.dll` / txt | Installer | Bundled B2E component | Managed/legacy-format component | Confirmed |
| `LhaForgeHelp.chm` | Installer | Documentation | Managed resource | Confirmed |
| `ReadMe.txt` | Installer | Documentation | Managed resource | Confirmed |
| `LhaForge.ini` | Runtime/configuration | User/common config | User data / compatibility config | High |
| `LFCaldix.ini` | LhaForge + LFCaldix | Shared update/config state | Compatibility data | Confirmed |
| `cldx\` | LFCaldix | Downloaded package docs/support | LFCaldix-managed preserved storage | High |
| external archive DLLs | LFCaldix/user | External backend | User-serviceable backend | High |
| temporary INI for LFAssist | Unregister/LhaForge | Ephemeral IPC/script | Generated temporary data | Confirmed |
| Registry file associations | LFAssist on behalf of LhaForge | Application registration state | Managed registration, restore external prior state | Confirmed |
| Registry shell COM entries | Shell DLL + LFAssist | Shell registration | Managed shell registration | Confirmed |

## 12. Implications for v1.7.0 ownership

The initial three-class model is not sufficient. The baseline suggests at least these semantic classes:

1. **Managed** — installation/repair/update owns the payload.
2. **User-serviceable** — LhaForge supports manual replacement/customization, notably external archive DLLs.
3. **User data / Configuration** — settings to preserve across repair/update by default.
4. **Generated** — temporary or diagnostic runtime output.
5. **Compatibility/package storage** — LFCaldix/cldx-derived material that is generated by a manager but should not automatically be treated as disposable cache.
6. **Legacy migration source** — detected v1.x artifacts awaiting preservation/translation/cleanup decisions.
7. **External prior state** — state such as a previous file association that must be restored, not claimed as LhaForge-owned.

A future Ownership Matrix should also contain **who may write**, **who may delete**, **repair policy**, **update policy**, **uninstall policy**, and **migration policy**, rather than only one ownership label.

## 13. Uninstall/repair lessons carried forward

The v1.x stack already separated application-specific deregistration from installer file removal. v1.7.0 should preserve the design principle while modernizing the implementation.

Current v1.7.0 direction:

```text
Uninstall.exe
  = user-facing recovery launcher

runtime\installer\UninstallCore.exe
  = independently functional uninstall/repair core
```

Safety principles derived from both legacy behavior and the new design:

- never require the original downloaded setup package for normal uninstall;
- do not delete user-managed external DLLs blindly;
- restore prior associations when possible;
- deregister x86/x64 shell state explicitly;
- log each migration/uninstall stage;
- preserve rollback information until success is committed;
- make missing/broken front-end uninstaller recoverable through the core and repair path.

## 14. Logging baseline vs v1.7.0

Legacy sources predominantly use debug traces and dialogs rather than a modern persistent logging subsystem.

v1.7.0 intentionally introduces a structured Logging Core with nine LhaForge levels:

```text
Emergency
Alert
Critical
Error
Warning
Notice
Info
Debug
Trace
```

Output targets are independently configurable:

- file only;
- Windows Event Log only;
- both.

The planned Windows Event Log provider uses LhaForge-owned application/service channels, with Operational and Debug as the baseline channel split.

This is a deliberate v1.7.0 extension, not a claimed v1.6.7 behavior.

## 15. Items still to verify before Baseline Final

The v1 document can be used for design now, but the following remain open for the final baseline:

1. Normalize the exact v1.6.7 main-application configuration path resolver and compare it with ShellExt 1.6.2 behavior.
2. Produce a complete Registry key/value inventory for LFAssist, ShellExt and installer handoff.
3. Produce the extension association matrix, including differences between Unregister 1.4.0 and LFAssist 1.6.0 extension lists.
4. Produce the complete per-DLL LFCaldix installation/destination/update matrix.
5. Identify which `cldx\` contents are reusable state, documentation, package residue or safe-to-regenerate data.
6. Document B2E ownership and generated files (`B2EMenu.dat` etc.) separately.
7. Document custom `/cfg` and other command-line compatibility behavior.
8. Confirm actual uninstall results in a disposable test environment: files, directories, Registry, associations and user configuration left behind.
9. Confirm first-run state changes from a clean install in a disposable test environment.
10. Compare historical source versions only where they explain final v1.6.7 behavior or migration edge cases.

These are validation tasks, not blockers for writing the v1.7.0 basic design.

## 16. Baseline design rule

The Legacy Baseline is evidence, not a requirement to reproduce every old implementation detail.

For each v1.7.0 decision, use this chain:

```text
Legacy evidence
    ↓
Original responsibility / user expectation
    ↓
Security and reliability constraints in supported Windows versions
    ↓
Retain / Modernize / Migrate / Replace / Retire
    ↓
Document why
```

The visible v1 philosophy, user workflows, external DLL ecosystem and recoverability should be preserved where practical, while implementation details that exist only because of historical Windows limitations may be replaced by safer modern equivalents.

## 17. Next documents derived from this baseline

1. `LhaForge-v1.6.7-ownership-matrix-v1.md`
2. `LhaForge-v1.6.7-registry-association-baseline-v1.md`
3. `LhaForge-v1.6.7-dll-lfcaldix-baseline-v1.md`
4. `LhaForge-v1.7.0-migration-matrix-v1.md`
5. `LhaForge-v1.7.0-basic-design-v1.md`

The ownership matrix should be produced next because it directly constrains installer, repair, migration and uninstall behavior.
