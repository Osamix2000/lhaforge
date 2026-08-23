# LhaForge

LhaForge v1.6.7を基盤として、v1系のUI・操作性・統合アーカイバDLLとの互換性を維持しながら、現代のWindows環境向けにModernizeするForkです。

> **現在は設計・開発準備段階です。**
>
> v1.7.0として利用可能なReleaseはまだありません。

## Project

* Base: LhaForge v1.6.7
* Development line: LhaForge v1.7.x
* Integration branch: `main-osamix`
* Active development branch: `develop-v1.7.0`
* Platform direction: Windows x64
* License: 修正BSDライセンス

LhaForge v2への移行ではなく、v1.6.7を直接の開発基準としてv1系を継続することを目的としています。

## Goals

LhaForge v1.xの特徴を可能な限り維持しながら、内部構造をModernizeします。

主な方針:

* v1系UI・操作性の維持
* 統合アーカイバDLLとの互換性維持
* LhaForge本体のx64化
* x86専用Legacy DLLを利用するLegacyHost
* 公式Upstream Libraryを優先できるManaged / Built-in Archive Backend
* Built-in Archive BackendによるFallbackと基本可用性
* Zstandard (`.zst` / `.tar.zst`) のBuilt-in圧縮・展開対応
* 公開仕様のZSTE (`.zste` / `.tar.zste`) によるAuthenticated Encryption対応
* Legacy Format対応の維持
* Unicode処理の改善
* Windows / macOS等のCross-platform Archiveでのファイル・フォルダー名互換性向上
* Archive Entry名の自動判定・Manual Encoding Override・Preview
* DLL Load / Archive Path Securityの強化
* Logging基盤の追加
* Summary FirstのArchive Result / Error UIとDiagnostic Export
* 現代Windows向けDPI・UI対応
* Installer / Repair / Migration / Uninstallの再設計
* v1.6.7環境からの安全なMigration
* `.git`や`.env`等を圧縮時に除外できる共通Input Filter
* `.DS_Store`、`__MACOSX`、`._*`等を解凍対象から除外できる共通Extraction Filter
* Archive名を利用した展開先Directory作成
* 必要な処理だけを昇格する最小権限設計
* Signed / Unsigned双方を許容するRelease設計
* SecurityとPerformanceを両立する共通Operation Planning
* Idle / 設定画面 / 通常UIでは不要なBackend、Process、Thread、Cacheを常駐させない軽量Runtime設計
* LibraryはLhaForge Release時にOfficial Upstream StableをReviewし、Validated Versionのみ更新・固定

## Archive Backend

v1.7.xでは、統合アーカイバDLL互換を正式に維持しながら、Formatごとに公式Upstream Libraryを利用するManaged / Built-in Backendを標準経路として採用できるArchitectureへModernizeします。Backendの一律順位ではなく、Security / Required Capability / Format-specific Policy / User Preferenceの順で選択します。

7-Zip Familyの設計Targetは次の通りです。

```text
Default / Recommended
    Official 7-Zip Library Backend
    └─ official 7z.dll

Legacy / Compatibility
    Integrated Archiver DLL Backend
    └─ 7-ZIP32.DLL
```

公式`7z.dll`は`7z.exe`を子Processとして呼び出すのではなく、LhaForge側のAdapterからLibrary APIを直接利用する方針です。PoC 4でLicense / API / Security / Regressionを検証し、通過したOfficial Stable VersionをProduction候補としてPinします。

`7-ZIP32.DLL`を含む統合アーカイバDLL、LFCaldix、`cldx`はv1系Compatibilityとして維持します。7-Zip FamilyではOptionからLegacy方式を選択できる設計とし、通常時に未使用BackendをLoadしたりx86 LegacyHostを起動したりしません。

PoC 2-Bから2-C4で固定使用する`7-ZIP32.DLL` 9.22.0.2は、v1.6.7互換性を測定するHistorical Regression Backendです。Productionを9.22.0.2へ固定する意図はなく、PoC 2-C3 / 2-C4完了後もHistorical Evidenceとして保持します。

Managed DependencyはLibrary単体で自動更新しません。LhaForge Release準備時にOfficial Upstream Stableを確認し、License / Security / API / Regression Gateを通過した場合のみLhaForgeと合わせて更新し、Version / SHA-256を固定します。詳細はADR-0007と[Dependency Management](docs/design/v1.7.0/dependencies.md)を参照してください。

## Zstandard / ZSTE

Zstandardは`.zst` / `.tar.zst`の標準互換を維持しつつ、Built-in Backendでの圧縮・展開を正式対応対象とします。

Zstandard Frame Format自体にはPassword-based Encryption機能がないため、暗号化Archiveを`.zst`の独自拡張として実装せず、Password-based Authenticated Encryption用の公開Container Formatとして`.zste` / `.tar.zste`を設計します。

ZSTEはLhaForge専用の非公開Formatにはせず、Format Specification、Encryption / Decryption Source、Test Vectorを公開し、第三者Softwareが独立実装できることを要件とします。

Cryptographic profileはArgon2id v1.3 + XChaCha20-Poly1305 secretstream-compatible constructionを基本方針とし、Argon2idの`m` / `t` / `p`、Record Framing等のWire Detailは実装・Fuzz・Cross-implementation Testを経てFreezeします。

Zstdの既定ProfileはUltra Level 22 + Auto / Performance threading、`--max`相当はDefault OFFのAdvanced Optionとします。

## Archive Operation Safety

v1.7.xではBackend種別に依存しないOperation Planningを導入し、圧縮対象と展開先をLhaForge側で共通管理します。

圧縮時には`.git`や`.env`等の共有したくない項目について、

* 除外しない
* 自動的に除外する
* 圧縮時に確認して決定する

といったPolicyを選択できる方向で設計しています。除外RuleはOptionから追加・削除・有効化・無効化できる構造とします。

解凍側にも共通Filterを用意し、`.DS_Store`、`__MACOSX`、`._*`等の不要Metadataを原則としてFilesystemへ書き出す前に除外できる設計とします。圧縮 / 解凍のRule Engineは共通化しつつ、Operationごとに適用範囲を指定できる構造とします。

Archive内のファイル・フォルダー名はFormat Metadata、Backend情報、UTF-8 / CP932等のCompatibility Policyから可能な限り自動判定し、閲覧 / 解凍前Preview / 実際の解凍で同じFilename Decode Policyを共有します。必要な場合はUserが文字コードを明示Overrideできる設計とします。

展開時には`sample.zip`を`sample\`、`source.tar.gz`を`source\`のように、Archive名を利用したSubdirectoryへ展開するOptionを提供します。

## Compatibility

v1.7.xでは、特に次のLegacy Compatibilityを重視します。

* LhaForge v1.6.7
* 統合アーカイバDLL
* LFCaldix
* `cldx`
* MenuEditor
* File Association
* Shell Extension
* 既存設定
* Legacy Archive Format

互換性のために安全性を犠牲にすることはせず、危険な旧実装については挙動差を文書化した上でModernizeします。

## Documentation

設計資料は`docs`以下に保存しています。

### Legacy

* [LhaForge v1.6.7 Legacy Baseline](docs/legacy/v1.6.7/legacy-baseline.md)
* [v1.6.7公式ソース検証](docs/legacy/v1.6.7/source-verification.md)

### v1.7.0 Design

* [Architecture](docs/design/v1.7.0/architecture.md)
* [Ownership Matrix](docs/design/v1.7.0/ownership-matrix.md)
* [Directory Layout](docs/design/v1.7.0/directory-layout.md)
* [Archive Backend Design](docs/design/v1.7.0/backend.md)
* [Migration Design](docs/design/v1.7.0/migration.md)
* [Installer Lifecycle Design](docs/design/v1.7.0/installer.md)
* [Logging Design](docs/design/v1.7.0/logging.md)
* [Encoding Design](docs/design/v1.7.0/encoding.md)
* [Archive Operation Design](docs/design/v1.7.0/archive-operations.md)
* [Archive Result / Error UI Design](docs/design/v1.7.0/archive-result-ui.md)
* [Signing and Privilege Design](docs/design/v1.7.0/signing.md)
* [Security Design](docs/design/v1.7.0/security.md)
* [Performance Design](docs/design/v1.7.0/performance.md)
* [ZSTE v1 Format Design](docs/design/v1.7.0/zste-format.md)
* [Design Review Cycle 1 (Historical)](docs/design/v1.7.0/design-review.md)
* [Design Review Cycle 2 - Pre PoC 2-C](docs/design/v1.7.0/design-review-cycle-2.md)
* [PoC Plan](docs/design/v1.7.0/poc-plan.md)
* [Risk Register](docs/design/v1.7.0/risk-register.md)
* [Build Modernization](docs/design/v1.7.0/build-modernization.md)
* [Compile Blocker Inventory](docs/design/v1.7.0/compile-blockers.md)
* [Regression Baseline](docs/design/v1.7.0/regression-baseline.md)
* [PoC 2-A UI Regression](docs/design/v1.7.0/regression-ui.md)
* [PoC 2-A Config Save / Reload Regression](docs/design/v1.7.0/regression-config.md)
* [PoC 2-B Archive Basic Operation Regression](docs/design/v1.7.0/regression-archive.md)
* [PoC 2-C Encoding / Path Regression Plan](docs/design/v1.7.0/regression-encoding.md)
* [PoC 2-C1 Direct Unicode Path Regression Result](docs/design/v1.7.0/regression-encoding-c1.md)
* [PoC 2-C2 Response File Encoding / Newline Regression Result](docs/design/v1.7.0/regression-encoding-c2.md)
* [Development Environment](docs/design/v1.7.0/development-environment.md)
* [Dependency Management](docs/design/v1.7.0/dependencies.md)

### Architecture Decision Records

* [ADR-0001: v1.6.7を開発基準とする](docs/adr/0001-v1.6.7-baseline.md)
* [ADR-0002: v1系外部DLL互換を維持する](docs/adr/0002-v1-external-dll-compatibility.md)
* [ADR-0003: x64本体とLegacyHostを採用する](docs/adr/0003-x64-main-and-legacyhost.md)
* [ADR-0004: Built-in BackendをFallbackとして持つ](docs/adr/0004-built-in-backend-fallback.md)
* [ADR-0005: 署名可能なRelease Architectureと最小権限設計を採用する](docs/adr/0005-signing-capable-release-and-least-privilege.md)
* [ADR-0006: 公開ZSTE FormatとAuthenticated Encryptionを採用する](docs/adr/0006-public-zste-format-and-crypto.md)
* [ADR-0007: 公式Upstream優先とFormat別Backend Policyを採用する](docs/adr/0007-upstream-first-and-backend-defaults.md)

## Development Status

PoC 1のModern x86 Build、PoC 2-AのUI / Configuration Regression、PoC 2-BのZIP Archive基本操作Regression、PoC 2-C1 Direct Unicode Path Regressionに加え、PoC 2-C2 Response File Regressionも完了しました。C2正常系は`MATCH`、AbnormalはOriginal / ModernのBehavioral Parityを確認した上でodd-length UTF-16を`SECURITY_CHANGE_REQUIRED`として固定しています。次はPoC 2-C3 ZIP Entry Name Metadata / Cross-platform oriented Fixtureへ進む段階です。

```text
Legacy Baseline              Done
Source Verification          Done
Architecture Decisions       In progress (ADR-0001 - 0007)
Ownership Design             Draft
Overall Architecture         Draft
Archive Operation Design     Draft
Signing / Privilege Design   Draft
Security Design              Draft
Performance Design           Draft
Directory Layout             Draft
Backend Design               Draft
Migration Design             Draft
Installer Design             Draft
Logging Design               Draft
Encoding Design              Draft
Design Review                Cycle 2 complete / PoC 2-C in progress
PoC Plan                     Draft
Risk Register                Draft
Build Modernization          PoC 1 complete
Regression Baseline          PoC 2-A / 2-B / 2-C1 / 2-C2 complete; PoC 2-C3 next
Development Environment      Verified
Dependency Management        BM-002 verified
x64 Migration                Not started
```

PoC 1用の開発環境定義としてRepository Rootに`.vsconfig`を用意しています。

標準環境はVisual Studio Community 2026 Stable + PlatformToolset v145 + MSVC 14.44 + Windows SDK 26100 familyです。詳細は[Development Environment](docs/design/v1.7.0/development-environment.md)を参照してください。

Visual Studio環境はPoC 1用構成で検証済みです。

WTLは`tools/restore-wtl.ps1`でRepository配下へRestoreし、`tools/verify-vs-environment.ps1`でVisual Studio / MSVC / SDKと合わせて確認します。Primary Profileは公式`source.txt`に合わせたWTL 9.1.5321で、Project Fileの旧固定Pathに対応するWTL 9.0.4140も比較用Profileとして保持します。

BM-003 Project Retarget、BM-004 Compile Blocker対応、BM-005 Debug / Release x86 Buildまで完了しました。Visual Studio Community 2026 / PlatformToolset v145 / MSVC 14.44 / SDK 26100 / WTL 9.1.5321で`Debug|Win32`と`Release|Win32`がBuild成功し、両方の`LhaForge.exe`でStartup Smoke TestもPassしています。

PoC 1のBuild Evidenceは次で再確認できます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-poc-x86-baseline.ps1
```

PoC 2-AのCancel-only UI / Configuration read / Isolation比較、およびConfig Save → Exit → ReloadのSemantic INI比較は完了し、`MATCH`となりました。

PoC 2-Bでは、Original / Modern x86へ同一SHA-256のx86 `7-ZIP32.DLL` 9.22.0.2を固定配置し、List / Test / Extract / Compress / Re-extractを比較しました。

最初のModern Release Listでは`0xC0000005` Crashを検出しました。WER Dump / PDB / Source archaeologyにより、`FileListModel.cpp`と`LogListDialog.cpp`がGlobal namespaceへ異なる`struct COMP`を定義していたODR違反を原因として特定し、Comparator typeを固有化する最小修正を行いました。

修正後は同一Reference ZIP / 同一`7-ZIP32.DLL`で全操作をFresh Runし、Extract / Roundtrip / ZIP semantics / external state / List・Test UIの全CriteriaがPassしました。最終Classificationは`MATCH`です。詳細は[PoC 2-B Archive Basic Operation Regression](docs/design/v1.7.0/regression-archive.md)を参照してください。

PoC 2-C1では、Japanese / Emoji / Supplementary Plane / Combining / NFC / NFDを含むDirect Archive File PathとOutput Directory PathをASCII-only内部Entryの専用Fixtureで分離検証し、Original / Modernの全Path ProbeがPASSしました。Unicodeを含むSource Directory / ZIP File Name / Entry NameでのCompressとRe-extractも双方PASSし、最終Classificationは`MATCH`です。詳細は[PoC 2-C1 Direct Unicode Path Regression Result](docs/design/v1.7.0/regression-encoding-c1.md)を参照してください。

PoC 2-C2正常系では、CP932、UTF-8 BOMあり / なし、UTF-16LE BOMあり / なし、UTF-16BE BOMあり、CRLF / LF / CR、Command Line途中のEncoding切替、`/@`保持 / `/$`削除を11 Caseで比較しました。Original / Modernとも11 / 11 PASS、最終Classificationは`MATCH`で、Generated ZIP byte SHA-256も11 / 11 pair一致しました。

PoC 2-C2 AbnormalではInvalid `/cp`、Invalid UTF-8、lone surrogate、odd-length UTF-16LE / BEを7 Caseで分離検証しました。Source-derived expectationを持つ5 CaseはOriginal / Modernとも一致し、odd-length UTF-16の2 CaseもBehavior signatureが一致しました。Crash / Timeout / External State Driftは検出されませんでしたが、奇数byte長UTF-16をValidationせずLegacy `WCHAR*`処理へ渡す挙動は互換要件として保存せず、最終Classificationを`SECURITY_CHANGE_REQUIRED`としています。詳細は[PoC 2-C2 Response File Encoding / Newline Regression Result](docs/design/v1.7.0/regression-encoding-c2.md)を参照してください。

次はPoC 2-C3 ZIP Entry Name Metadata / Cross-platform oriented Fixtureへ進みます。Actual x64化はPoC 2-C3 / 2-C4を含む必要なRegression Baselineを固定した後に開始します。

## Development Principles

このプロジェクトでは、v1.6.7のソースを一度に全面Rewriteしません。

Legacy Behaviorを調査・記録した上で、段階的に、

```text
Legacy Baseline
      ↓
Architecture
      ↓
Build Modernization
      ↓
Regression Verification
      ↓
x64 / Backend Modernization
      ↓
Security / Performance / Compatibility
      ↓
v1.7.0
```

と進めます。

元の設計・挙動と、新しい設計・変更理由の双方をDocumentationおよびGit履歴に残します。

## Upstream

Original LhaForge:

* Author: Claybird
* Repository: https://github.com/Claybird/lhaforge
* Website: https://claybird.sakura.ne.jp/garage/lhaforge/

本プロジェクトはLhaForge v1.6.7を基盤とするModernization Forkです。

## License

LhaForgeは修正BSDライセンスで公開されています。

各External Archive DLL、Built-in Backendで使用するLibrary、その他Third-party Componentには、それぞれ個別のLicenseが適用される場合があります。
