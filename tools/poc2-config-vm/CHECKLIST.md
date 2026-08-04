# PoC 2-A 第2段階：設定Save / Reload比較

このTest Kitは、Original v1.6.7とModern x86を同じ初期INIから起動し、設定保存・終了・再起動・再読込を比較します。

## 前提

- Windows VMのClean Snapshotを使用する
- LhaForgeをインストールしていない状態にする
- Networkは切断したままでよい
- ZIPをVMの固定Local Diskへ展開する
- VMware Shared Folder上から直接実行しない
- PowerShellは管理者として実行しない

UAC確認、LFAssistの実行Error、関連付け変更らしき表示が出た場合は、その場で中止してSnapshotへ戻してください。

---

## 1. 初期化

KitのRootで通常権限PowerShellを開きます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\initialize-config-regression.ps1
```

Existing LhaForge AssociationまたはShell Extensionが検出された場合は中止します。その場合はClean Snapshotへ戻してください。

---

## 2. Original v1.6.7

`original\Launch.cmd`を起動します。

次の5項目だけを変更します。

### 一般設定

1. 「圧縮/解凍のログ」→「処理結果表示の条件」を **毎回表示**
2. 「出力先の種類が次の場合、確認」→ **ネットワーク**をON
3. 「出力先フォルダが存在しない場合」→ **自動的に作成**

### 圧縮共通設定

4. **出力先フォルダを開く**をOFF

### ファイル一覧ウィンドウ

5. **ESCキーで終了**をON

変更してはいけないPage:

- シェル拡張
- 関連付け
- DLL自動更新
- ショートカット作成

指定項目を変更後、**OK**で保存します。

もう一度`original\Launch.cmd`を起動し、5項目が保持されていることを画面で確認します。2回目は**キャンセル**で閉じます。

確認後:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-config-result.ps1 -Target Original -ReloadVerified
```

---

## 3. Modern x86

`modern\Launch.cmd`を起動し、Originalと同じ5項目だけを同じ値へ変更します。

**OK**で保存後、再度`modern\Launch.cmd`を起動して5項目が保持されていることを確認し、2回目は**キャンセル**で閉じます。

確認後:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-config-result.ps1 -Target Modern -ReloadVerified
```

---

## 4. 比較

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-config-results.ps1
```

期待結果:

```text
[OK] Expected saved values passed for Original and Modern.
[OK] Original and Modern semantic INI contents match.
[OK] Original and Modern LFCaldix.ini hashes match.
[OK] External AppData, ProgramData, and registry state remained unchanged.
[POC2-CONFIG] Classification: MATCH
[POC2-CONFIG] PoC 2-A config save/reload regression passed.
```

Evidenceは`evidence\`へ保存されます。
