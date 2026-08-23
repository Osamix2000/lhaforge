# LhaForge v1.7.0 PoC 2-C2 Response File Abnormal Regression Checklist

Status: Tooling prepared / execution pending

This checklist is separate from the completed PoC 2-C2 normal baseline.

Do **not** rerun `initialize-response-regression.ps1` for this phase. The abnormal initializer uses separate directories:

- `fixture-response-abnormal`
- `original\response-abnormal-results`
- `modern\response-abnormal-results`
- `evidence-response-abnormal`

The completed normal fixture/evidence directories are not initialized or removed by the abnormal tooling.

## Preconditions

- Run inside the dedicated Windows VM.
- Use a non-elevated Windows PowerShell 5.1 session.
- The VM kit must be extracted to a local fixed disk.
- The VM kit path must contain ASCII characters only.
- ANSI code page must remain 932.
- Do not change system locale or code page for this test.
- Close all LhaForge processes.
- Keep a restorable VM snapshot before starting.
- The final two odd-length UTF-16 cases are boundary-sensitive and must be run last.
- Every abnormal command rechecks non-elevated Windows PowerShell 5.1, ACP932, the fixed local/ASCII kit path, and initialized target binary identities before proceeding.

From the extracted VM kit root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\initialize-response-abnormal-regression.ps1"
```

Expected initializer summary:

```text
[POC2-RSP-ABN] PoC 2-C2 abnormal VM initialization passed.
...
[POC2-RSP-ABN] Abnormal cases  : 7
```

If initialization fails, stop. Do not run any case.

## Case policy

Run **one case at a time**. Read and close any LhaForge error dialog normally.

After each command:

1. Confirm the script saved a JSON run record.
2. If the script throws because of timeout, crash, or an expectation mismatch, stop immediately.
3. Do not use `-Force` merely to make the test pass. Preserve the first evidence and diagnose the cause.
4. For `observe-only` cases, review the saved evidence before continuing.

The two invalid `/cp` cases place one valid direct input before the invalid switch. This deliberately keeps `FileList` non-empty so `main()` does not replace `PROCESS_INVALID` with the configuration dialog after parsing fails.

The first five cases have source-derived expectations. The final two odd-length UTF-16 cases are `observe-only`; Original behavior becomes the behavioral baseline for the Modern comparison, but parity is not treated as proof that the legacy behavior is safe.

## Original

Run in this exact order:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId invalid-cp-value
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId invalid-cp-syntax
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId invalid-utf8-at
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId invalid-utf8-dollar
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId utf16le-lone-surrogate-at
```

Before the next two commands, confirm the VM snapshot is still available and no LhaForge process remains.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId utf16le-odd-at
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target original -CaseId utf16be-odd-at
```

If all seven Original run records exist and no stop condition occurred:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\capture-response-abnormal-result.ps1" -Target original
```

Do not run Modern until the Original capture is complete.

## Modern

Run the same cases in the same order:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId invalid-cp-value
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId invalid-cp-syntax
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId invalid-utf8-at
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId invalid-utf8-dollar
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId utf16le-lone-surrogate-at
```

Before the next two commands, confirm the VM snapshot is still available and no LhaForge process remains.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId utf16le-odd-at
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run-response-abnormal-case.ps1" -Target modern -CaseId utf16be-odd-at
```

Then:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\capture-response-abnormal-result.ps1" -Target modern
```

## Compare

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\compare-response-abnormal-results.ps1"
```

Expected comparison when Original and Modern remain behaviorally compatible with the current source:

```text
[POC2-RSP-ABN] Classification: SECURITY_CHANGE_REQUIRED
```

`SECURITY_CHANGE_REQUIRED` is intentional for this baseline. It means behavioral parity was obtained, but the odd-length UTF-16 source paths require hardening rather than being preserved as a compatibility requirement.

The comparison still verifies that:

- Original and Modern used the same abnormal raw response bytes and argument plans.
- The first five cases matched the source-derived expectations for both targets.
- The two odd-length UTF-16 cases produced the same recorded Original/Modern behavior signature.
- No target timed out or produced a crash-like process exit.
- Response-file post-state and any generated archive semantics matched between Original and Modern; a corrupt/unparseable generated ZIP is preserved as evidence and forces review.
- Manual dialog observations are known and agree between Original and Modern.
- External AppData/ProgramData state did not change from initialization.
- Tracked `%TEMP%\zip*.tmp` state did not change from initialization.

Classification meanings for this phase:

- `SECURITY_CHANGE_REQUIRED`: expected if all compatibility checks match and only the pre-identified odd-length UTF-16 safety disposition remains.
- `MATCH`: possible only if no case is marked as requiring safety hardening.
- `REVIEW_REQUIRED`: an observed mismatch, crash, timeout, state drift, or expectation failure requires diagnosis.

If classification is `REVIEW_REQUIRED`, stop and preserve the entire `evidence-response-abnormal` directory and both target `response-abnormal-results` directories.

## Evidence to retain

After a successful comparison, retain at least:

```text
evidence-response-abnormal\state-before.json
evidence-response-abnormal\original-result.json
evidence-response-abnormal\modern-result.json
evidence-response-abnormal\comparison.json
```

Also retain the first-run per-case records until the abnormal phase is formally documented.
