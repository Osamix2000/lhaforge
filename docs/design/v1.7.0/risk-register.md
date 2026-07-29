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
| R-001 | High | 現行BuildがVS2013 / old Toolset / Machine固有WTL Pathへ依存 | Build不能、再現性欠如 | Modern x86 Buildを最初のPoCにする |
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

---

## 2. Critical Risks

現時点のCritical Riskは、

```text
R-006 Archive extraction security
R-009 Lifecycle data loss
```

である。

この2つは「互換性のためにRiskを許容する」対象にしない。

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
