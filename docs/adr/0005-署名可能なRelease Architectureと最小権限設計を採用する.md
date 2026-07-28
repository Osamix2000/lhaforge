# ADR-0005: 署名可能なRelease Architectureと最小権限設計を採用する

* Status: Accepted
* Target: LhaForge v1.7.x
* Related:
  * ADR-0001: v1.6.7を開発基準とする
  * ADR-0003: x64本体とLegacyHostを採用する

## Context

LhaForge v1.7.xでは、通常の圧縮・展開・設定操作に管理者権限は必要ない一方、Installer、Repair、Update、Uninstall、Machine-wideなRegistry変更、Shell Extension登録等では管理者権限が必要になる場合がある。

また、Public ReleaseではAuthenticodeコード署名を導入できれば、Publisher Identityの提示、改ざん検出、署名済みComponentの検証等に利用できる。

しかし、Public Trustされたコード署名証明書の取得・維持には費用、本人確認、秘密鍵保護、Signing Service等の運用が必要になる可能性があるため、v1.7.xの成立条件として署名を必須にすると、配布方式や開発継続性を不必要に制約する。

そのため、Privilege Separationは必須のArchitecture要件としつつ、Authenticode署名は後から導入・変更・不採用を選択できる構造が必要である。

## Decision

LhaForge v1.7.xでは、次の方針を採用する。

1. 通常Applicationは最小権限で実行する。
2. 管理者権限はSystem-wideな変更が必要な操作に限定する。
3. First-party BinaryはAuthenticode署名可能な構造とする。
4. Public Releaseにおける署名の有無はRelease Policyとして別途決定する。
5. 署名が存在しない場合でもLhaForge本体、Installer、Uninstaller等が正常に動作できるようにする。
6. 署名が存在する場合は追加のIntegrity / Publisher Validationとして利用できるようにする。
7. Signing Provider、CA、HSM、Cloud Signing Service等の特定方式にApplication Architectureを依存させない。
8. 未署名ReleaseでもHash、Manifest、Package Metadata、固定Path等によるIntegrity確認を可能な範囲で行う。

## Privilege Separation

基本構造は次の通りとする。

```text
通常権限
├─ LhaForge.exe
├─ MenuEditor.exe
├─ LhaForgeLegacyHost.exe
├─ Update UI / Check
└─ その他、System-wide変更を伴わない処理
        │
        │ 必要な操作のときだけ明示的にElevation
        ▼
管理者権限
├─ Install Core
├─ Repair Core
├─ Update Core（Program Files等の更新時）
├─ Uninstall Core
└─ Machine-wide Registration Helper
```

LhaForge.exeそのものを常時`requireAdministrator`にはしない。

System-wide変更が必要になった時点で、目的を限定したHelper/Coreを明示的に昇格させる。

## Signing Model

SigningはBuildそのものから分離したOptional Release Stepとする。

```text
Build
  ↓
Test
  ↓
Package Preparation
  ↓
Optional Signing
  ├─ Unsigned
  └─ Signed + Timestamp
  ↓
Final Package Validation
  ↓
SHA-256 / Release Metadata
  ↓
Release
```

同じSource / Build PipelineからSigned / Unsignedの双方を生成できることを目標とする。

署名方式の違いによってApplication BehaviorやFile Layoutが変わる設計は避ける。

## First-party and Third-party Binaries

LhaForge Project自身がBuild・管理するBinaryはSigning対象にできる。

例:

```text
LhaForge.exe
MenuEditor.exe
Unregister.exe
LhaForgeLegacyHost.exe
Installer / Uninstaller Components
Shell Extension
Updater Components
```

一方、External Archive DLL等のThird-party BinaryをLhaForgeのPublisher Identityで再署名することは原則行わない。

Third-party BinaryはOwnership、License、Original Signature、Hash、Version、API Capability等を別途評価する。

## Integrity without Public Signing

Public Trustされた署名を利用しないReleaseでも、Integrity確認を放棄しない。

利用可能な手段:

* SHA-256
* Package Manifest
* Expected File List
* File Size / Version Metadata
* 固定されたInstall Path / Relative Path
* Download Metadata
* GitHub Release等で公開したHashとの照合

署名が利用可能な場合はこれらに加え、Authenticode Signature、Expected Publisher、Timestamp等を検証できる。

```text
Common Validation
    ↓
Hash / Manifest / Path / Version
    ↓
署名あり？
    ├─ No  → Common Validation結果で継続
    └─ Yes → Signature / Publisherも追加検証
```

特に管理者権限で起動する内部Componentについては、Pathだけを信用して起動する設計を避ける。

## Security

署名はSecurity強化要素の一つであり、署名そのものをSandboxや安全性保証とはみなさない。

署名の有無に関係なく、次を継続する。

* Least Privilege
* 入力Validation
* DLL Search Path制限
* Path Validation
* Package / Update Integrity確認
* IPC相手のValidation
* Error Handling
* Logging

## Consequences

### Positive

* Public Trustされた証明書を用意できなくてもRelease可能
* 将来Signing Serviceを導入してもApplication設計を変更しなくてよい
* 通常操作で不要なUAC Promptを出さずに済む
* System-wide処理のPrivilege Boundaryが明確になる
* Signed ReleaseではPublisher / Integrity Validationを追加できる
* Signing Providerの変更に対応しやすい

### Negative

* Signed / Unsigned双方を考慮したTestが必要
* 署名なしの場合はWindows上のPublisher表示等の利点を得られない
* Integrity Validationを署名だけに任せられないため、Manifest / Hash等の設計も必要
* Elevated Helperとの境界・通信設計が増える

## Alternatives Considered

### Public Releaseを必ずAuthenticode署名する

現時点では採用しない。

安全性・利用者体験上は望ましいが、証明書取得・費用・運用方式がProjectの成立条件になってしまう。

### コード署名を一切考慮しない

採用しない。

将来署名を導入する際にInstaller、Updater、Release Pipeline等の再設計が必要になるためである。

### Application全体を常時管理者権限で実行する

採用しない。

通常のArchive操作に不要な権限を与えることになり、SecurityおよびUser Experienceの双方で不適切である。

## Notes

署名方式はv1.7.0 Release直前に再評価できる。

候補にはPublic CA、OSS向けSigning Service、その他将来利用可能な仕組みを含むが、このADRでは特定Providerを採用しない。
