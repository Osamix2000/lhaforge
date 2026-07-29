# LhaForge v1.7.0 Ownership Matrix

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7
- Purpose: v1.6.7の実態を基に、v1.7.xにおけるファイル・設定・コンポーネントの所有権、Repair、Migration、Uninstall方針を整理する。
- Note: Lifecycle設計で確定したPolicyは本表へ反映し、技術制約が残る項目のみ`TBD`として維持する。

## Ownership Matrix

| 対象                | v1.6.7役割               | 旧所有主体             | v1.7.0分類                       | Repair   | Upgrade/Migration | Uninstall | 確度        |
| ----------------- | ---------------------- | ----------------- | ------------------------------ | -------- | ----------------- | --------- | --------- |
| LhaForge.exe      | 本体                     | Installer         | Managed                        | 上書き可     | 更新                | 削除        | Confirmed |
| MenuEditor.exe    | メニュー編集                 | Installer         | Managed / User-facing          | 上書き可     | 更新                | 削除        | Confirmed |
| Unregister.exe    | 登録解除補助                 | Installer         | Managed / Legacy-facing        | 上書き可     | 更新                | 削除        | Confirmed |
| LFAssist.exe      | 登録操作補助                 | Installer         | Managed                        | 上書き可     | 更新                | 削除        | Confirmed |
| LFAssist64.exe    | 64bit側登録補助             | Installer         | Managed                        | 上書き可     | 更新                | 削除        | Confirmed |
| ShellExtDLL.dll   | x86 Shell Extension    | Installer         | Managed                        | 上書き可     | 更新                | 削除        | Confirmed |
| ShellExtDLL64.dll | x64 Shell Extension    | Installer         | Managed                        | 上書き可     | 更新                | 削除        | Confirmed |
| LFCaldix.exe      | DLL取得/管理               | Installer         | Managed / Legacy compatibility | 上書き可     | 更新/移行             | 削除        | Confirmed |
| LhaForge.ini      | ユーザー設定                 | LhaForge/User     | User configuration             | 上書き禁止    | 保持/移行             | 既定保持 / 明示削除 | High      |
| LFCaldix.ini      | DLL管理設定                | LhaForge/LFCaldix | Shared compatibility config    | 無条件上書き禁止 | 移行                | 既定保持 / 所有確認後に明示削除 | Confirmed |
| cldx\             | DLL説明書等                | LFCaldix          | Legacy managed assets          | 保持       | 保持/移行             | 既定保持 / 明示削除 | Confirmed |
| 外部Archive DLL     | Backend                | LFCaldix/User     | User-serviceable Backend       | 原則上書き禁止  | 保持/評価             | 既定保持 / 明示削除 | High      |
| b2e32.dll         | Bundled B2E support    | Installer         | Managed                        | 上書き可     | 更新/互換確認           | 削除        | Confirmed |
| epuninst.exe      | 旧Installer Uninstaller | Installer         | Legacy migration input         | 修復対象外    | 新方式へ移行            | 旧環境時のみ    | High      |
