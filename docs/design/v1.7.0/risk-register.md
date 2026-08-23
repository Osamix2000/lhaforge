# LhaForge v1.7.0 Risk Register

- Status: Draft
- Target: LhaForge v1.7.x
- Purpose: 実装前後の主要Riskを見える化し、CompatibilityだけでなくSecurity、Data Integrity、Performance、Maintenanceを含めて管理する。

Risk level:

```text
Critical
High
Medium
Low
```

---

## 1. Risk Register

| ID | Level | Risk | Main impact | Mitigation / validation |
| --- | --- | --- | --- | --- |
| R-001 | High | VS2013 Solution metadata / VS2017世代Project metadata / v120系Toolset / Machine固有WTL Pathが混在 | Build不能、再現性欠如、Historical環境の誤認 | Modern x86 Buildを最初のPoCにし、Dependency / Toolsetを個別に固定する |
| R-002 | High | `Release-X64`名称を実x64と誤認 | x64計画の誤判断 | Project Platform / TargetMachineを基準に判定 |
| R-003 | High | 32bit pointer / time / struct assumption | x64 crash、Data corruption | x64 audit、compile warning、regression test |
| R-004 | High | Legacy DLLがx86-onlyまたはAPI差異を持つ | Format compatibility低下 | LegacyHost、per-DLL support matrix |
| R-005 | High | External DLLの不正 / 脆弱 / crash | App crash、任意Code実行Risk | restricted load、probe、LegacyHost isolation、policy |
| R-006 | Critical | Archive Path Traversal / Reparse / ADS等 | 任意Pathへの書込 | Central Security Guard、negative tests |
| R-007 | High | Archive Bomb / Resource Exhaustion | Disk / Memory / CPU枯渇 | resource budget、bounded queue、cancel |
| R-008 | High | Filter除外後にBackendがDirectoryを再走査 | `.env`等の機密File混入 | `ExactInputSet` Capability必須化 |
| R-009 | Critical | Migration / UninstallでUser Dataを削除 | Data loss | Ownership、default preserve、journal、rollback |
| R-010 | High | Elevated Helperが任意Path / Commandを受理 | Privilege escalation | narrow IPC contract、allowlist、path validation |
| R-011 | High | Installer途中Crash / Power loss | 半端なInstall状態 | staged apply、journal、resume / rollback / repair |
| R-012 | Medium | Shell Extension lock / Explorer lifecycle | Update / uninstall failure | delayed replacement / restart policy PoC |
| R-013 | High | Legacy Encodingを一括変換 | 設定 / 日本語 / archive name破損 | Unicode Core + Boundary conversion、byte-preserving migration |
| R-014 | Medium | Source File Encodingを早期一括変更 | Diff巨大化、Build破損 | baseline build後に段階実施 |
| R-015 | Medium | LoggingにSecret / Full Pathを残す | Information disclosure | structured redaction、default path minimization |
| R-016 | Medium | Logging大量発生 | Performance / disk impact | bounded async queue、Trace suppression |
| R-017 | High | Built-in LibraryのLicense / redistribution不整合 | Release不能 | Library採用前License review |
| R-018 | Medium | External DLL同梱License不整合 | Distribution制限 | Ownership / license manifest、必要ならdownload方式 |
| R-019 | Medium | Code Signingなし | UAC / SmartScreen UX低下 | Optional signing architecture、hash publication |
| R-020 | High | Update package spoof / corruption | malicious update | HTTPS source、hash、manifest、署名利用時はsignature validation |
| R-021 | Medium | Backend selectionが複雑化 | 予測不能、Support困難 | deterministic ranking、selection reason logging |
| R-022 | Medium | Capability Cache stale | 誤ったBackend選択 | file identity / version validation、invalidate policy |
| R-023 | Medium | LegacyHost IPCがchatty | x86 backend性能低下 | batching、session reuse、measure IPC count |
| R-024 | Medium | UI modernizationでv1操作性を失う | User experience regression | UI変更を後期Phase、regression screenshots / behavior |
| R-025 | Medium | Minimum Windows Versionを早期に決めすぎる | Modern API利用制約 /不要な互換負担 | Build / API audit後にDecision |
| R-026 | Critical | ZSTE Parser / KDF / authenticated stream実装不備 | Plaintext漏洩、改ざん見逃し、Data loss | Public specification/source、vetted crypto libraries、no custom primitive、test vectors、fuzz、independent decoder、security review |
| R-027 | High | ZSTE HeaderのKDF / length値によるResource Exhaustion | Memory / CPU DoS、allocation failure | pre-auth hard limits、overflow check、bounded record/header、policy limits |
| R-028 | High | Weak passwordに対するOffline Guessing | ZSTE内容の復号 | Argon2id v1.3、強いdefault KDF cost、password UX、KDF parameter persistence |
| R-029 | High | ZSTE Wire Formatを早期FreezeしてInterop欠陥を固定 | 第三者互換不能、将来Format break | pre-wire-freeze status、canonical vectors、second implementation、RC前extension/MIME再確認 |
| R-030 | High | Archive Entry NameのEncoding誤判定 / Lossy Decode | 文字化け、Wrong Path、Collision、Cross-platform互換性低下 | Raw Name保持、Format-aware decode、Confidence、Manual Override、Unicode collision validation、PoC 2-C |
| R-031 | High | Extraction Filter要求時にBackendがEntryを再列挙 / 全展開 | `.DS_Store`等の不要File出力、Security / Privacy / Cleanup問題 | `SelectiveExtract` / `ExactOutputSet` Capability、別Backend、Unsupported明示、安全なStaging Policy |
| R-032 | Medium | Archive Result / Error原因を過剰推定 | Userへ誤原因表示、Support誤誘導、問題切り分け悪化 | Stable Error Code、Raw Backend Log保持、`UnknownFailure` / Unknown Reasonを正式化 |
| R-033 | Medium | Huge Result / Raw LogでError UIが巨大化・重くなる | Error確認不能、Memory / UI responsiveness低下 | Summary First、Virtual List、Scroll、Work Area基準Size、Minimum Size、Resize / Maximize |
| R-034 | High | Managed Runtime Libraryを無検証で最新版へ更新 | API/ABI break、Regression、脆弱Version混入、Release不安定化 | Release-coupled update、Official Upstream、Version/SHA pin、License/Security/Regression Gate |
| R-035 | Medium | 第三者Fork / 改良版を安易にProduction Dependencyへ採用 | Supply-chain増加、License追跡複雑化、Maintenance停止 | Upstream First、公式不足時だけ例外採用、差分Audit / reproducible build / Exit条件 |
| R-036 | Medium | Backend / Settings / Watcherを常時LoadしてIdle Memory・Thread数が増加 | v1系の軽快さ低下、常駐Memory増加、Handle/Thread leak | Lazy load、no background dependency polling、bounded cache、Idle/Settings resource benchmark |

---

## 2. Critical Risks

現時点のCritical Riskは、

```text
R-006 Archive extraction security
R-009 Lifecycle data loss
R-026 ZSTE cryptographic / parser correctness
```

である。

この3つは「互換性のためにRiskを許容する」対象にしない。

Legacy BackendがSecurity Contractを満たせない場合、そのOperationではBackendを利用しない判断を許容する。

---

## 3. Build Modernization Risks

最初に解消するRisk:

```text
R-001
R-002
R-003
R-013
R-014
R-025
```

Build環境をModernizeする段階では、Feature追加と大規模Refactorを同時に行わない。

まずx86 Baseline Buildを成立させ、差分を限定する。

---

## 4. Backend Risks

Backend実装前に重点管理:

```text
R-004
R-005
R-008
R-017
R-018
R-021
R-022
R-023
R-026
R-027
R-028
R-029
R-030
R-031
R-032
R-033
R-034
R-035
R-036
```

Support Format数を増やす前に、少数FamilyでCommon Backend Modelが成立することを優先する。

---

## 5. Installer / Migration Risks

重点管理:

```text
R-009
R-010
R-011
R-012
R-020
```

Installer Frameworkの選択より、Ownership / Journal / Recovery Contractを先に固定する。

---

## 6. Risk Acceptance Policy

Riskを残したままReleaseする場合は、最低限次を明示する。

- Risk ID
- User impact
- 発生条件
- Workaround
- なぜv1.7.0で解決しないか
- Follow-up version

Security / Data Lossに関するCritical Riskは、Known Issueとして単純受容せず、Operation disable等の安全側Fallbackを優先する。

---

## 7. Review Policy

Risk Registerは次のタイミングで更新する。

- PoC完了
- Architecture Decision変更
- New third-party dependency採用
- Installer / updater設計変更
- Security issue発見
- Release candidate作成

Riskが解消した場合もRowを削除せず、将来Status列を追加して履歴を残せる構造へ発展させる。
