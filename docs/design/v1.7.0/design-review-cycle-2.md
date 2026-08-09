# LhaForge v1.7.0 Design Review Cycle 2 - Pre PoC 2-C

- Status: Complete
- Review date: 2026-08-09
- Target: LhaForge v1.7.x
- Baseline review point: `develop-v1.7.0` after PoC 2-B MATCH and README Zstandard / ZSTE repair
- Purpose: PoC 2-C開始前に、Repositoryの設計方針、Regression Evidence、追加要求、古い記述を横断確認し、Architecture driftがないことを確認する。

Related documents:

- `design-review.md` (Cycle 1 / historical)
- `architecture.md`
- `archive-operations.md`
- `archive-result-ui.md`
- `backend.md`
- `encoding.md`
- `logging.md`
- `security.md`
- `performance.md`
- `poc-plan.md`
- `regression-baseline.md`
- `regression-archive.md`
- `regression-encoding.md`
- `risk-register.md`

---

## 1. Review Result

PoC 2-C開始前の横断Reviewでは、v1.7.xのCore Architectureを破棄・再設計する必要がある矛盾は確認していない。

次のCore Principleは維持されている。

1. v1.6.7を直接のBaselineとする。
2. v1系UI / 操作性 / External Archive DLL文化を維持する。
3. Main Applicationはx64、x86 DLLはLegacyHost経由とする。
4. Backend優先順位はExternal x64 -> External x86 + LegacyHost -> Built-inとする。
5. Built-in BackendはExternal DLLを置き換えるものではなくFallbackとする。
6. Security / Compatibility / Operation PolicyはBackend共通Layerで扱う。
7. Normal Operationはnon-elevated、System-wide変更だけを必要時にElevationする。
8. Signed / Unsigned Release双方を成立させる。
9. Migration / UninstallではUser / External / Unknown DataをDefault preserveする。
10. Application内部TextはUnicodeを基本とし、Legacy EncodingはBoundaryで明示変換する。
11. User File ContentのEncoding / BOM / NewlineをExtract時に勝手に変換しない。
12. Securityのために必要なValidationをPerformance理由で省略しない。

PoC 2-Bで発見したODR違反修正はLegacy Behavior変更を狙ったものではなく、Modern Releaseで顕在化したSource correctness defectを解消するCompatibility Fixとして整合している。

---

## 2. PoC 2-B State

PoC 2-Bは`Complete / MATCH`。

Historical Regression Backend:

```text
7-ZIP32.DLL 9.22.0.2
SHA-256 A82D2B10960F9EBAF5B9D56E2F495C72C22F5DE542740D585AB14CB0B291999C
```

このVersionはHistorical Baseline Fixtureであり、v1.7.xのNormal Supported Backendを9.22.0.2へ固定する方針ではない。

Current external DLL、x86 Legacy DLL + LegacyHost、Built-in BackendはRegression Baselineを維持した上で別PhaseとしてModernizeする。

---

## 3. New Accepted Encoding / Cross-platform Direction

PoC 2-C前に次を正式な設計方向として追加する。

### 3.1 Shared Filename Decode Layer

File List、Extraction Preview、実際のExtractで同じFilename Decode Policyを利用する。

閲覧時だけ正しいがExtract後に文字化けするような別実装を避ける。

### 3.2 Raw Entry Name Preservation

Backend / FormatがRaw Entry Name Bytesを提供できる場合は保持する。

目的:

- Auto Decode
- Manual Encoding Override
- Re-decode
- Diagnostic
- Ambiguous Encoding比較

Raw bytesを取得できないBackendではCapabilityとして制限を明示する。

### 3.3 User-facing Encoding Override

解凍Dialog:

```text
解凍時のファイル・フォルダー名の文字コード
[ 自動判定（推奨） ]

解凍後のファイル・フォルダー名が文字化けする場合に変更してください。
```

Archive File List:

```text
ファイル・フォルダー名の文字コード
[ 自動判定（推奨） ]
```

通常はAutoをDefaultとし、UTF-8、CP932 / Windows-31J、Backend Default、Format-specific option等をCapabilityに応じて提供する。

EncodingがFormat上確定しているCaseでもOverrideを許可するAdvanced OptionをDefault Offで用意する方向とする。

### 3.4 Preview

Modern Extraction UIではPreview Button方式を採用する方向とする。

Preview WindowでFilename Encodingを切り替え、Entry表示を再Decodeできるようにする。

Previewは必須操作にはしない。

### 3.5 Cross-platform Compatibility

Windows / macOS間で発生し得るFilename Metadata / Unicode Normalization差をPoC 2-Cへ含める。

macOS実機は現時点で利用できないため、Deterministic Fixtureを先に使用し、実macOS生成Archiveは将来Evidenceとして追加する。

---

## 4. New Accepted Extraction Filter Direction

Compression ExclusionだけでなくExtraction側にも共通Rule Engineを拡張する。

初期macOS metadata preset候補:

```text
.DS_Store
__MACOSX/
._*
```

原則:

```text
Archive Entry
  -> Decode
  -> Security Validation
  -> Extraction Filter
  -> Final Extraction Set
  -> Backend
```

除外対象を一度Filesystemへ展開してから削除する方式をDefaultにしない。

Selective Extract / Exact Output SetをBackend Capabilityとして扱い、満たせないBackendでFilterが要求された場合は別Backend、明確なFailure、安全なStaging等をPolicyとして選択する。

Security Validationは「どうせ除外するEntryだから」という理由で無条件Skipしない。

---

## 5. New Accepted Archive Result / Error UI Direction

Result / Error UIはSummary FirstへModernizeする。

同時にRaw Backend Logを保持し、Developer Diagnosis能力を失わない。

採用方向:

- Stable LhaForge Error Code
- Backend raw result / raw log
- `Success / PartialSuccess / Failed / UnknownFailure / Canceled`
- Unknownを正式なResultとして扱う
- Error / Warning優先表示
- Large ResultはVirtualized / Scroll
- User Resize
- Minimum Size
- Maximize
- Initial HeightはMonitor Work Areaの約65%を候補
- Initial Widthは現行相当をBaselineにDPI / Work Areaで調整
- `ログをコピー`
- `ログをファイルとして保存`
- Simplified / Detailed log
- `.txt` / `.log`
- `LhaForge-{Operation}-{YYYYMMDD}-{HHMMSS}.{ext}`
- Source File / Lineは取得可能時のみ
- Build / Commit / Module / RVA / Exception Code / Raw Logを優先Diagnosticとする

詳細は`archive-result-ui.md`へ分離する。

---

## 6. Existing Source Compatibility Findings Relevant to PoC 2-C

現在Sourceには、PoC 2-Cで観測すべきLegacy Encoding経路が存在する。

- Unicode BuildではWide Command Lineを利用する。
- Response Fileは`/cp:*`によるCode Page指定を持つ。
- 7-ZIP32 AdapterはUTF-8 Response File + `-scsUTF-8`を使用する。
- 7-ZIP32 AdapterはUnicode Modeを有効にする。
- Legacy ANSI / ACP依存経路も残る。
- Existing Archive Entry ModelはRaw Name Bytesを常時保持する設計ではない。

このためPoC 2-CではSourceを先にModernizeせずOriginal / Modern Behaviorを固定する。

---

## 7. Stale / Inconsistent Documentation Found

### 7.1 `regression-baseline.md`

PoC 2-A節に、

```text
次はPoC 2-BのArchive基本操作Regressionへ進む。
```

というPoC 2-B完了後も残ったHistorical文が存在した。

Current Stateに合わせPoC 2-A / PoC 2-B完了、PoC 2-C nextへ修正する。

### 7.2 `design-review.md`

Cycle 1のDocumentであるため、`Build environment not selected`、`Reproducible modern build not available`等の当時のHistorical Stateが残っている。

内容をCurrent Stateへ上書きしてCycle 1のEvidenceを失わない。

Cycle 1はHistorical Documentとして保持し、冒頭から本Cycle 2へ案内する。

### 7.3 PoC 9 Logging / Encoding

PoC 2-CもEncodingを扱うためScopeが重複して見える。

整理:

```text
PoC 2-C
  Legacy Original vs Modern x86 Encoding / Path Regression Baseline

PoC 9
  Modernized Logging / Encoding Architecture validation
```

として目的を分離する。

---

## 8. Risk Review

既存Risk RegisterのR-013 Legacy Encoding破損、R-008 Exact Input Set、R-015 Logging sensitive data等は引き続き有効。

追加管理対象:

- Filename Auto Decode誤判定による文字化け / Collision
- Extraction FilterをBackendが正確に実行できず不要Entryを出力するRisk
- Result / Error原因を過剰推定して誤表示するRisk
- Huge Result / Raw LogによるUI / Resource問題

`risk-register.md`へ追加する。

---

## 9. Pre-PoC 2-C Gate

PoC 2-C開始前に次を満たす。

- Encoding Policy更新
- Extraction Filter設計更新
- Result / Error UI設計追加
- Regression Baselineのstale文修正
- PoC 2-C Test Plan追加
- Risk Register更新
- README / Architecture link更新
- Cycle 1 Design ReviewをHistoricalとして保持
- このCycle 2 ReviewをCommit

これらがCommit / Pushされた後にPoC 2-C Test Kit実装へ進む。

---

## 10. Decision

**PoC 2-Cへ進むArchitecture Blockerはない。**

ただしPoC 2-Cは新機能実装ではなく、Original v1.6.7とModern x86のEncoding / Path Regression Evidence取得を先に行う。

PoC 2-CでLegacy limitationやModern-only regressionが見つかった場合は、後続Caseを無理に進めず原因調査し、EvidenceをDocumentへ反映する。
