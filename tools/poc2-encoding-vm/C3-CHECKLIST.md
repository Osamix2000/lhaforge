# PoC 2-C3 Formal VM Checklist

このKitはPoC 2-C3 ZIP Entry Name MetadataのOriginal v1.6.7 / Modern x86 Runtime比較専用です。

## このSessionでは実行しない

Host PCだけで作業する日は、Repository側で次まで確認すれば終了です。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-c3-regression.ps1 ...
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-poc2-c3-vm-kit.ps1
```

VM内の以下の手順は次回以降に実施します。

## VM前提

- 非管理者Windows PowerShell 5.1 Desktop
- ACP932 / ja-JP
- Local fixed diskへKitを展開
- Original / Modernとも同一`7-ZIP32.DLL` 9.22.0.2 x86
- LhaForge Processが起動していない
- VM Snapshotから開始
- Fixture ZIPは編集・再圧縮しない

## 1. Initialize

Kit Rootで実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\initialize-c3-regression.ps1
```

15 / 15 Fixture identity checkがPASSすること。

## 2. Original

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-c3-target.ps1 -Target original
```

各CaseについてList → Test → Extractの順に進む。

Listは表示候補を番号または`m/e/o`で記録する。Unicode文字をConsoleへ手入力しない。

Test / ExtractもScriptのPromptへ回答する。Error / Warning / Otherを選んだ場合は、必要に応じて表示内容をObservation Noteへ残す。

各Operation後にAppData / ProgramDataのBaseline差分を確認する。Unexpected mutationを検出した場合は、そのOperationのRun Recordを保存した上で停止する。

Crash、Unexpected external mutation、Wrong-directory extraction、Security-relevant behaviorがあれば停止する。

完了後:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-c3-result.ps1 -Target original
```

## 3. Modern

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-c3-target.ps1 -Target modern
```

完了後:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-c3-result.ps1 -Target modern
```

## 4. Compare

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-c3-results.ps1
```

`MATCH`ならBehavioral parity。

`REGRESSION`は`spec-valid`または`cross-platform-observe`でOriginal / Modern差異を検出した状態。

`legacy-observe` / `metadata-observe` / `conflict-observe` / `malformed-observe`でOriginal / Modern差異が出た場合は、自動的にRegressionと断定せず`UNKNOWN`としてReviewへ送る。

`UNKNOWN`は上記Review対象、valid Fixture failure、manual `other`、または自動判定できない結果がある状態。

Malformed / Conflict CaseがOriginal / ModernでMATCHしていても、そのBehaviorをProduction Compatibility Requirementとして保存するとは限らない。`EXPECTED_DIFFERENCE` / `SECURITY_CHANGE_REQUIRED`を含む最終ClassificationはEvidence確認後にDocument側で決定する。

## 5. Evidence

`evidence-c3\`をそのまま保存する。

最低限:

```text
state-before-c3.json
original-c3-result.json
modern-c3-result.json
comparison-c3.json
```

各Targetの`results\c3-run-records\`と`results\c3-extract\`もEvidence候補として保持する。

## Stop Conditions

- Process crash / access violation
- Fixture hash mismatch
- Backend hash/version mismatch
- Fixture以外のFile deletion / overwrite
- Wrong-directory extraction
- Unexpected AppData / ProgramData mutation
- Security-relevant behavior
- Modern-only unexpected behavior

Malformed FixtureでArchive Errorになること自体はStop理由ではない。
