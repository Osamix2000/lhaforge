# LhaForge v1.7.0 Signing and Privilege Design

* Status: Draft
* Target: LhaForge v1.7.x
* Related ADR: ADR-0005

## 1. Purpose

コード署名の採用有無に依存せず、LhaForge v1.7.xを安全にBuild・配布・実行できる構造を定義する。

本設計では、Privilege Separationを必須要件、Authenticode SigningをOptionalなRelease機能として扱う。

## 2. Principles

* 通常処理は一般ユーザー権限で実行する
* System-wide変更のみ必要時にElevationする
* Signed / Unsigned Releaseの双方を許容する
* Applicationの正常動作を署名の存在に依存させない
* 署名がある場合は追加のValidationに使用する
* Signing ProviderへBuild / Runtime Architectureを密結合しない
* Public SigningがなくてもHash / Manifest等によるIntegrity確認を行う

## 3. Privilege Classification

### Normally Unelevated

* `LhaForge.exe`
* `MenuEditor.exe`
* `LhaForgeLegacyHost.exe`
* Archive List / Test / Extract / Create
* User-level Configuration
* Update Check / Download

### Elevation May Be Required

* Program FilesへのInstall / Update / Delete
* HKLM等Machine-wide Registry操作
* Machine-wide File Association
* Shell Extension登録・解除
* Repair
* Uninstall

実際の操作単位でElevation要否を判定し、Component名だけを理由に常時管理者実行にはしない。

## 4. First-party Signing Targets

Signingを採用する場合、First-party executable codeを基本対象とする。

例:

* `LhaForge.exe`
* `MenuEditor.exe`
* `Unregister.exe`
* `LhaForgeLegacyHost.exe`
* Shell Extension DLL
* Installer Components
* Repair / Update Components
* `Uninstall.exe`
* `UninstallCore.exe`

Third-party Archive DLLは原則としてLhaForge側で再署名しない。

## 5. Release Modes

### Unsigned Release

```text
Build
↓
Test
↓
Package Validation
↓
SHA-256生成
↓
Release
```

### Signed Release

```text
Build
↓
Test
↓
First-party Binary Signing
↓
Signature Verification
↓
Package Build
↓
Package / Setup Signing
↓
Signature Verification
↓
SHA-256生成
↓
Release
```

Signing後にBinaryを変更しない。

## 6. Runtime Validation

内部Componentを実行する際は、署名の有無だけに依存しない。

Validation候補:

1. Expected Path
2. Package Manifest
3. Expected Component Identity
4. Version / Architecture
5. Hash（利用可能な場合）
6. Authenticode Signature（存在する場合）
7. Expected Publisher（Release Policyで定義されている場合）

署名なしReleaseであること自体をRuntime Errorにはしない。

## 7. Update Validation

Updaterを実装する場合は、最低限DownloadしたArtifactのHash / Release Metadataを検証する。

Signed ReleaseではSignature Validationを追加できる。

```text
Download
↓
Release Metadata
↓
Hash Validation
↓
Package Structure Validation
↓
Signature available?
├─ No  → Unsigned Policyに従う
└─ Yes → Signature / Publisher / Timestamp Validation
↓
Update
```

署名検証結果が異常な場合は、既存Installを破壊する前に停止する。

## 8. Key Material

Public Signingを採用する場合、秘密鍵をSource Repositoryや通常のBuild Artifactへ含めない。

* Source Treeへ秘密鍵を保存しない
* `.pfx`等をGitへCommitしない
* PasswordをSource / Scriptへ直接記述しない
* HSM / Hardware Token / Signing Service等を利用できる構造を許容する

Development用Test CertificateとPublic Release用Identityは分離する。

## 9. Logging

Signing / Validation関連では次を記録可能にする。

* Signature presence
* Validation result
* Publisher identity（存在する場合）
* Timestamp validation result
* Hash validation result
* Component path / version

秘密鍵情報やCredentialはLogへ出力しない。

## 10. Open Items

* Public ReleaseでSigningを採用するか
* Signing Provider
* Public Publisher Identity
* CI/CD Signing方式
* Release Manifest形式
* RuntimeでのHash Validation範囲
* Timestamp Policy

これらはRelease段階で決定してよく、Application Architectureの成立条件とはしない。
