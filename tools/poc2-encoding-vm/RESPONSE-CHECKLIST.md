# PoC 2-C2 Response File Encoding / Newline Regression Checklist

このChecklistは **PoC 2-C2 Response File Encoding / Newline** の正常系Baselineを対象にします。

PoC 2-C1のEvidenceとは別に、`fixture-response`、`response-results`、`evidence-response`を使用します。C1の11件のRun Recordや`evidence`を上書きしません。

## 重要

- VM KitはVMの**ローカル固定ディスク**へ展開してください。
- Windows PowerShell 5.1を**非管理者**で起動してください。
- 初期化時にANSI Code Pageが`932`であることをGateします。異なる場合は設定を自動変更せず停止してください。
- `LhaForge.exe`が起動中の状態で初期化しないでください。
- Crash、Access Violation、想定外のファイル削除、外部AppData / ProgramData変更が起きた場合は**その時点で停止**してください。
- 正常系Caseはすべて自動判定です。1つでもFailureが出たら後続Caseへ進まずEvidenceを保持してください。
- Response File自体のPathはASCII-onlyです。Response Fileの**内容Encoding / BOM / Newline / Parser state**だけを主変数として扱います。
- `/@`は読込後にResponse Fileを保持、`/$`は正常読込後にResponse Fileを削除するBehaviorも検証します。
- Invalid UTF-8 / Invalid UTF-16 / invalid `/cp`等のAbnormal Caseは、この正常系Baseline完了後に別途扱います。

## 1. 初期化

VM Kit Rootで実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\initialize-response-regression.ps1
```

成功条件:

```text
[POC2-RSP] PoC 2-C2 VM initialization passed.
[POC2-RSP] ANSI code page  : 932
[POC2-RSP] Normal cases    : 11
```

## 2. Original

次を**上から1つずつ**実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId sjis-crlf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf8-nobom-crlf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf8-bom-crlf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf16le-bom-crlf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf16be-bom-crlf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf16le-nobom-crlf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf8-nobom-lf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId utf8-nobom-cr
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId sequence-sjis-then-utf8
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId sequence-utf8-reset-sjis
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-response-case.ps1 -Target original -CaseId dollar-delete-utf8
```

各CaseはResponse Fileから選択されたInput SetをZIPへ圧縮し、ZIP内部のEntry Name + Payload SHA-256 FingerprintをExpected Input Setと比較します。

`sequence-sjis-then-utf8`は、既定SJISで最初のResponse Fileを読み、その後`/cp:utf8`へ切り替えて2つ目を読みます。

`sequence-utf8-reset-sjis`は、`/cp:utf8`で1つ目を読んだ後、bare `/cp`でSJISへ戻して2つ目を読みます。

`dollar-delete-utf8`は`/$...`を使用し、Working Copyが読込後に削除されたことまで自動確認します。他のCaseは`/@...`を使用し、Working Copyがbyte-identicalのまま残ることを確認します。

## 3. Original Evidence Capture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-response-result.ps1 -Target original
```

期待:

```text
[POC2-RSP] Run records: 11
```

## 4. Modern

Section 2の11 Caseを`-Target modern`で同じ順番で実行します。

## 5. Modern Evidence Capture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-response-result.ps1 -Target modern
```

期待:

```text
[POC2-RSP] Run records: 11
```

## 6. Compare

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-response-results.ps1
```

最終期待:

```text
[POC2-RSP] Classification: MATCH
```

Generated ZIPのbyte SHA-256一致数はObservationとして表示しますが、Primary Pass条件ではありません。Primary EvidenceはResponse File raw identity、Parserで選択されたInput Set、ZIP Entry Name、Payload SHA-256、`/@` / `/$` post-stateです。

`REVIEW_REQUIRED`、Crash、Fingerprint Failure、Response File post-state failureが出た場合は、その状態のままEvidenceを保持して原因調査へ移ります。
