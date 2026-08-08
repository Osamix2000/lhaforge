# PoC 2-B Archive Regression VM Checklist

このKitはOriginal LhaForge v1.6.7とModern x86 Buildに、同一SHA-256の`7-ZIP32.DLL`を与えてZIP基本操作を比較するためのものです。

## 0. VM checkpoint

PoC 2-A完了時のSnapshot:

```text
PoC2-A Config Regression Passed
```

PoC 2-B開始時はこのSnapshotへ戻してから、Kit ZIPをVMのローカル固定Diskへ展開します。

Shared FolderやNetwork Driveから直接実行しません。

## 1. Initialize

VMの通常権限PowerShellで、Kit Rootから実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\initialize-archive-regression.ps1
```

期待:

```text
[POC2-ARCHIVE] VM initialization passed.
```

この時点で以下が確認されます。

- Original / Modern `LhaForge.exe`がx86
- Original / Modernで同一`7-ZIP32.DLL`を使用
- DLLがx86
- EXE / DLL / Reference ZIPのSHA-256がHost生成時Manifestと一致
- Fixture内容が一致
- KitがLocal Fixed Disk
- LhaForge Processが起動していない

## 2. Original

### List

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target original -Operation list
```

List Windowで少なくとも次のLogical Treeが確認できること:

```text
another/data.txt
empty.txt
nested/binary.bin
nested/child.txt
root.txt
```

Directory Entryの見せ方やRow数そのものはPrimary判定にしません。

Windowを閉じるとConsoleへ確認が出るので、内容が正しければ`y`を入力します。

### Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target original -Operation test
```

Archive Test Dialogで正常判定・Archive Errorなしを確認して閉じ、Consoleで`y`を入力します。

### Extract

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target original -Operation extract
```

### Compress

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target original -Operation compress
```

固定条件:

```text
ZIP
Deflate
Level 5
Top directory is not stored
```

### Re-extract

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target original -Operation reextract
```

### Capture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-archive-result.ps1 -Target original
```

## 3. Modern

Originalと同じ順序で実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target modern -Operation list
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target modern -Operation test
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target modern -Operation extract
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target modern -Operation compress
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-archive-operation.ps1 -Target modern -Operation reextract
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-archive-result.ps1 -Target modern
```

## 4. Compare

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-archive-results.ps1
```

最終期待:

```text
[POC2-ARCHIVE] Classification: MATCH
```

Primary criteria:

- Reference ZIPのExtract結果がFixtureとPath / Size / SHA-256一致
- Original / Modern Extract結果が一致
- Original圧縮ZIPを再展開するとFixtureと一致
- Modern圧縮ZIPを再展開するとFixtureと一致
- Original / Modernの生成ZIPが.NET ZipArchiveで読める
- 生成ZIPのLogical File List / SizeがFixtureと一致
- List / Test UIが双方で成功
- Module-local Configを使用し、AppData / ProgramDataのLhaForge内容を変更しない

## 5. Important comparison rule

圧縮後ZIPのBinary SHA-256がOriginalとModernで同じことは要求しません。

ZIPにはTimestamp、Entry Metadata、Ordering、Encoder実装差などが入り得るため、Primary判定は次とします。

```text
Fixture
  -> LhaForge compression
  -> ZIP can be opened
  -> LhaForge re-extraction
  -> file path / size / SHA-256 equivalence
```

生成ZIP自体のSHA-256はEvidenceとして記録しますが、Binary一致だけでRegression判定しません。

## 6. Stop conditions

次の場合は先へ進まず、その画面またはConsole出力を共有します。

- DLL load error
- DLL too old
- ListでArchiveを開けない
- TestがNG
- ExtractでError Dialog
- CompressでError Dialog
- `roundtrip.zip`が作成されない
- Re-extractでError
- Compareが`MISMATCH`
- Crash
