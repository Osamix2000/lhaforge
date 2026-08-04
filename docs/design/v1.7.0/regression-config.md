# PoC 2-A Config Save / Reload Regression

- Status: VM preflight in progress
- Scope: Original v1.6.7 vs Modern x86
- Test environment: clean Windows VM
- User context: non-elevated
- Network: disconnected is acceptable

Related:

- [Regression Baseline](regression-baseline.md)
- [PoC 2-A UI Regression](regression-ui.md)
- [PoC Plan](poc-plan.md)
- [Legacy Baseline](../../legacy/v1.6.7/legacy-baseline.md)

---

## 1. Source findings

設定DialogでOKを押すと、`CConfigDialog::OnOK`は次を行う。

1. `CConfigManager::LoadConfig`で直前のINIを再読込
2. 全Config Pageの`OnApply()`を呼ぶ
3. 全Config Pageの`StoreConfig()`を呼ぶ
4. Assistant要求数が1以上なら`LFAssist64.exe` / `LFAssist.exe`を起動
5. Dialog終了後、`CConfigManager::SaveConfig()`で`LhaForge.ini`を保存

このため「一般設定だけを変更したからINI以外へ絶対に触れない」とは、Source確認なしには扱えない。

### Association Page

Association Pageは、既存Associationが`LhaForgeArchive_*`であり、現在実行中のStaged EXE PathとOpen Commandが一致しない場合にAssistantを要求する。またAssociation CheckboxやIconを変更した場合もAssistantを要求する。

### Shell Extension Page

Shell Extension Pageは現在の登録状態を画面へ読み込み、Checkboxを切り替えた場合にAssistantを要求する。`OnApply()`自体はTemporary Assistant INIへ要求値を書くが、Assistant要求数が0なら最後にTemporary INIは削除される。

したがってConfig Save Regressionは、LhaForge Association / Shell Extensionが存在しないClean VMで実行する。

---

## 2. Safe test fields

初回Config Save Regressionでは、INI内へ保存されるだけで、Apply時に外部Processを直接起動しない次の項目を使用する。

| UI Page | UI項目 | INI | Initial | Test value |
|---|---|---|---:|---:|
| 一般設定 | 処理結果表示の条件：毎回表示 | `[LogView] LogViewEvent` | 0 | 1 |
| 一般設定 | ネットワークを確認 | `[Output] WarnNetwork` | 0 | 1 |
| 一般設定 | 出力先Folderを自動的に作成 | `[Output] OnDirNotFound` | 2 | 1 |
| 圧縮共通設定 | 出力先Folderを開く | `[Compress] OpenFolder` | 1 | 0 |
| File一覧Window | ESCキーで終了 | `[FileListWindow] ExitWithEscape` | 0 | 1 |

Update抑止は常に次を維持する。

```ini
[Update]
AskUpdate=0
```

Association、Shell Extension、DLL Update、Shortcut Pageは操作しない。

---

## 3. Why the VM kit is separate

BuildはHost、Regression実行はVMへ分離する。

```text
Host repository
  tools/prepare-poc2-config-regression.ps1
      ↓
  .baseline/poc2-config/poc2-config-vm-kit.zip
      ↓ copy
Windows VM local fixed disk
  Original save/reload
  Modern save/reload
  semantic INI comparison
  external state comparison
```

VMへVisual StudioやRepository全体を入れる必要はない。

Shared Folder上から直接実行するとFilesystem・権限・Path差がTestへ混入するため、KitをVM Local Diskへ展開する。

---

## 4. Prepare on host

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-config-regression.ps1 -OriginalExe "C:\Program Files (x86)\LhaForge\LhaForge.exe"
```

再作成:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\prepare-poc2-config-regression.ps1 -OriginalExe "C:\Program Files (x86)\LhaForge\LhaForge.exe" -Force
```

生成物:

```text
.baseline\poc2-config\vm-kit\
.baseline\poc2-config\poc2-config-vm-kit.zip
```

---

## 5. VM preflight

### Windows PowerShell 5.1 registry-query compatibility

初回VM実行では、存在しないRegistry Keyを`reg.exe query ... 2>&1`で確認した際、Windows PowerShell 5.1が標準エラーを`NativeCommandError`へ変換し、`$ErrorActionPreference = 'Stop'`によってPreflightが中断した。

Clean VMで対象Keyが存在しないこと自体は正常であるため、次のように修正した。

1. PowerShell Registry Providerの`Test-Path -LiteralPath`でKey存在を先に確認
2. 存在しないKeyは`exists=false`として記録
3. 存在するKeyだけ`reg.exe query /s`でFingerprintを取得
4. `reg.exe`標準エラーをPowerShell Error Streamへ結合しない
5. 存在確認済みKeyのQueryが失敗した場合は安全側で停止

これにより、Clean VMの「Registry Keyなし」と実際のQuery失敗を区別する。

VM Kitの`initialize-config-regression.ps1`は次を確認する。

- LhaForge Processが起動していない
- PowerShellが非昇格
- KitがFixed Local Disk上にある
- `LhaForgeArchive_*` Associationが存在しない
- v1.6.7 Shell Extension CLSIDが存在しない

その後、Original / Modern INIを同じTemplateへResetし、次をSnapshotする。

- `%APPDATA%\LhaForge`
- `%ProgramData%\LhaForge`
- 対象Archive ExtensionのHKCR状態
- Shell Extension関連CLSID
- ContextMenuHandlers / DragDropHandlers

---

## 6. Semantic comparison

`CConfigManager::SaveConfig()`はUTF-16LE BOMで全Sectionを書き直す。そのためBinary Hashだけではなく、Section / Key / ValueへParseして比較する。

比較項目:

- 選定した5設定値
- Original / Modernの全INI Semantic Entry
- INI Encoding
- `LFCaldix.ini` Hash
- AppData / ProgramData状態
- Association / Shell Registry状態

SectionやKeyの並び順差だけではRegressionとしない。

---

## 7. Pass criteria

```text
Original save                      PASS
Original reload                    PASS
Modern save                        PASS
Modern reload                      PASS
Selected five values               PASS
Semantic INI contents              MATCH
LFCaldix.ini                       MATCH
External AppData / ProgramData     unchanged
Association / Shell registry       unchanged
UAC / LFAssist execution           none
Crash                              none
```

Classificationは`MATCH`を期待する。

---

## 8. Next step

Pass後はPoC 2-Bとして、固定ZIP Fixtureと固定Archive DLLを用いたList / Test / Extract / Compress Regressionへ進む。
