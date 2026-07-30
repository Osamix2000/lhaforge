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
* Built-in Archive BackendによるFallback
* Legacy Format対応の維持
* Unicode処理の改善
* DLL Load / Archive Path Securityの強化
* Logging基盤の追加
* 現代Windows向けDPI・UI対応
* Installer / Repair / Migration / Uninstallの再設計
* v1.6.7環境からの安全なMigration
* `.git`や`.env`等を圧縮時に除外できる共通Input Filter
* Archive名を利用した展開先Directory作成
* 必要な処理だけを昇格する最小権限設計
* Signed / Unsigned双方を許容するRelease設計
* SecurityとPerformanceを両立する共通Operation Planning

## Archive Backend

v1.7.xでは、外部アーカイバDLLを正式なBackendとして維持します。

基本的なBackend選択方針:

```text
External x64 DLL
        ↓
External x86 DLL + LegacyHost
        ↓
Built-in Backend
        ↓
Error
```

Built-in Backendは外部DLL方式を廃止するためのものではなく、External Backendが利用できない場合のFallbackおよび基本可用性確保を目的とします。

## Archive Operation Safety

v1.7.xではBackend種別に依存しないOperation Planningを導入し、圧縮対象と展開先をLhaForge側で共通管理します。

圧縮時には`.git`や`.env`等の共有したくない項目について、

* 除外しない
* 自動的に除外する
* 圧縮時に確認して決定する

といったPolicyを選択できる方向で設計しています。除外RuleはOptionから追加・削除・有効化・無効化できる構造とします。

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
* [Signing and Privilege Design](docs/design/v1.7.0/signing.md)
* [Security Design](docs/design/v1.7.0/security.md)
* [Performance Design](docs/design/v1.7.0/performance.md)
* [Design Review](docs/design/v1.7.0/design-review.md)
* [PoC Plan](docs/design/v1.7.0/poc-plan.md)
* [Risk Register](docs/design/v1.7.0/risk-register.md)
* [Build Modernization](docs/design/v1.7.0/build-modernization.md)
* [Compile Blocker Inventory](docs/design/v1.7.0/compile-blockers.md)
* [Regression Baseline](docs/design/v1.7.0/regression-baseline.md)
* [Development Environment](docs/design/v1.7.0/development-environment.md)
* [Dependency Management](docs/design/v1.7.0/dependencies.md)

### Architecture Decision Records

* [ADR-0001: v1.6.7を開発基準とする](docs/adr/0001-v1.6.7-baseline.md)
* [ADR-0002: v1系外部DLL互換を維持する](docs/adr/0002-v1-external-dll-compatibility.md)
* [ADR-0003: x64本体とLegacyHostを採用する](docs/adr/0003-x64-main-and-legacyhost.md)
* [ADR-0004: Built-in BackendをFallbackとして持つ](docs/adr/0004-built-in-backend-fallback.md)
* [ADR-0005: 署名可能なRelease Architectureと最小権限設計を採用する](docs/adr/0005-signing-capable-release-and-least-privilege.md)

## Development Status

PoC 1のModern x86 Buildは完了し、現在はPoC 2のRegression Baseline確認へ進んでいます。

```text
Legacy Baseline              Done
Source Verification          Done
Architecture Decisions       In progress
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
Design Review                Draft
PoC Plan                     Draft
Risk Register                Draft
Build Modernization          PoC 1 complete
Regression Baseline          PoC 2 in progress
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
powershell -NoProfile -ExecutionPolicy Bypass -File .	oolserify-poc-x86-baseline.ps1
```

現在はPoC 2として、Modern x86 BuildをOriginal v1.6.7とのBehavior比較基準に固定する[Regression Baseline](docs/design/v1.7.0/regression-baseline.md)へ進んでいます。Actual x64化はこのBaseline確認後に開始します。

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
