# PoC 2-C1 Direct Unicode Path / UTF-8 ZIP Regression Checklist

このVM Kitは **PoC 2-C1だけ** を対象にします。PoC 2-C2（Response File）、2-C3（Legacy ZIP Metadata）、2-C4（Compound Archive）はC1の結果を確認してから追加します。

## 重要

- VM KitはVMの**ローカル固定ディスク**へ展開してください。
- PowerShellは**非管理者**で起動してください。
- `LhaForge.exe`が起動中の状態で初期化しないでください。
- Crash、Access Violation、想定外のファイル削除、外部AppData/ProgramData変更、誤った場所への展開が起きた場合は**その時点で停止**してください。
- 各コマンドは順番に実行し、異常が出たら次へ進まず出力を保存してください。
- VM Kit内の`original`と`modern`は同一byte列の`7-ZIP32.DLL`を使用します。
- Unicode FixtureはVM上でCode Pointから生成します。VM Kit ZIP自体にはUnicode Pathを含めません。

## 1. 初期化

VM Kit Rootで実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\initialize-encoding-regression.ps1
```

成功条件:

```text
[POC2-ENC] PoC 2-C1 VM initialization passed.
```

## 2. Original - List

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation list
```

List Windowで日本語、Emoji、Supplementary Plane、Combining Character、NFC/NFDを確認し、文字化けやArchive Errorが無ければ`y`。

## 3. Original - Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation test
```

正常なら`y`。

## 4. Original - Direct Path Probe

次を**1つずつ**実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId ascii
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId japanese
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId emoji
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId supplementary
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId combining
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId nfc
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation pathprobe -CaseId nfd
```

各CaseはArchive File NameとOutput Directory Nameの両方に対象Unicodeを含めます。抽出結果はFixtureのCode Point + Payload SHA-256 Fingerprintと比較されます。

## 5. Original - Compress / Re-extract

Unicodeを含むSource Directory PathとEntry Nameを使います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation compress
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-encoding-case.ps1 -Target original -Operation reextract
```

## 6. Original Evidence Capture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-encoding-result.ps1 -Target original
```

## 7. Modern

上記2～6を`-Target modern`で同じ順番で実行します。

## 8. Modern Evidence Capture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-encoding-result.ps1 -Target modern
```

## 9. Compare

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-encoding-results.ps1
```

最終的に、

```text
[POC2-ENC] Classification: MATCH
```

ならC1の自動比較条件は一致です。

`REVIEW_REQUIRED`、Crash、Manual Failure、Fingerprint Failureが出た場合は、その状態のままEvidenceを保持して原因調査へ移ります。
