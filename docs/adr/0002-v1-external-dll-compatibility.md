# ADR-0002: v1系外部DLL互換を維持する

* Status: Accepted
* Target: LhaForge v1.7.x
* Related:

  * ADR-0001: v1.6.7を開発基準とする
  * ADR-0003: x64本体とLegacyHostを採用する
  * ADR-0004: Built-in BackendをFallbackとして持つ

## Context

LhaForge v1.xは、統合アーカイバプロジェクトを中心とした外部アーカイバDLLを利用する設計を特徴としている。

v1.6.7では、7-ZIP32.DLL、TAR32.DLL、UNLHA32.DLL、UNRAR32.DLLなど複数の外部DLLを利用し、LFCaldixによる取得・更新と、ユーザーによる手動差し替えの双方が可能であった。

この外部DLL方式は、単なる内部実装ではなく、LhaForge v1.xの互換性、対応形式、運用方法を構成する重要な要素である。

LhaForge v2では内部アーカイブエンジン主体の設計へ移行したが、v1.7.xではv2への再設計ではなく、v1.6.7を基礎としたModernizationを目的とする。

そのため、外部DLL方式を廃止すると、v1.xとして維持したい次の特徴が失われる。

* 統合アーカイバDLLとの互換性
* ユーザーによるDLLの更新・差し替え
* LhaForge本体とは独立したBackend更新
* 古いアーカイブ形式への対応
* v1.xから継続して利用している環境との互換性

## Decision

LhaForge v1.7.xでは、v1系外部アーカイバDLLとの互換性を正式に維持する。

外部DLLはLhaForgeの第一級Archive Backendとして扱い、Built-in Backendより優先して利用する。

基本的なBackend選択順序は次の通りとする。

1. x64外部DLL
2. x86外部DLL（LegacyHost経由）
3. Built-in Backend
4. 利用可能なBackendが存在しない場合はエラー

外部DLLの配置先は、v1.7.xではアーキテクチャを明確化するため、原則として次の構造を採用する。

```text
LhaForge\
└─ dll\
   ├─ x64\
   └─ x86\
```

`dll`ディレクトリは内部実装専用領域とはせず、ユーザーが確認・保守・差し替え可能な領域として扱う。

### DLLの利用可否判定

DLLが存在するだけでは利用可能とは判定しない。

少なくとも次の確認を行う。

* ファイルの存在
* PE Architectureの確認
* DLLのロード可否
* 必要なExport関数の存在
* API Version
* 初期化処理の成否
* 必要なCapability
* 必要に応じて簡易動作確認

Backendは拡張子だけではなくCapabilityによって選択する。

Capabilityの例:

* Open
* List
* Test
* Extract
* Create
* Update
* Delete
* Password
* Encryption
* MultiVolume
* Unicode

同じ形式であっても、操作内容によって異なるBackendが選択されることを許容する。

## External DLL Ownership

外部アーカイバDLLは、LhaForge本体の通常のManaged Binaryとは区別する。

ユーザーまたはDLL管理機構によって更新される可能性があるため、Installer、Repair、Updaterが無条件に上書きしてはならない。

基本分類は次の通りとする。

```text
LhaForge.exe等
    Managed

dll\x64\
dll\x86\
    User-serviceable / External Backend
```

既存DLLを更新する場合は、少なくとも次を考慮する。

* DLL Version
* File Hash
* Installerによる配置物か
* LFCaldix等による取得物か
* ユーザーが手動配置したものか
* 新旧どちらが利用可能か

所有者を判定できない既存DLLについては、原則として保持する。

## LFCaldixとの関係

v1.xで利用されてきたLFCaldixおよび`cldx`については、Legacy Compatibilityの一部として扱う。

`cldx`はRuntime DLLの単純な格納場所ではなく、LFCaldixが取得したDLLに付属する説明書等を保存するLegacy Asset領域である。

そのため、次の役割を分離する。

```text
dll\
    実際にArchive Backendとして使用するDLL

cldx\
    LFCaldixが管理する説明書・関連資料・Legacy Asset
```

MigrationやUninstallにおいて`cldx`を一時キャッシュとして無条件削除してはならない。

## Security

v1.x互換DLLを利用する一方で、DLLロード方式そのものはv1.6.7の実装をそのまま維持しない。

v1.7.xでは次の方向へ強化する。

* DLLの絶対パス指定
* DLL Search Pathの制限
* 適切なLoadLibraryEx系APIの利用
* Architecture確認
* 不正または予期しないDLLのロード防止
* DLLロード失敗時の明確なLogging

互換性の維持は、過去の安全性上の問題まで再現することを意味しない。

## Consequences

### Positive

* v1.xの特徴を維持できる
* ユーザーが外部DLLを更新できる
* Built-in Backendが未対応のLegacy Formatを維持できる
* Archive BackendをLhaForge本体とは独立して更新できる
* v1.6.7からのMigrationが容易になる
* 現代版のx64 DLLが存在する場合はそのまま活用できる

### Negative

* Backend管理が複雑になる
* DLLごとの差異を吸収するCompatibility Layerが必要になる
* x86専用DLLのためにLegacyHostが必要になる
* 外部DLLの品質や制約をLhaForge側だけでは完全に管理できない
* RepairやUpdate時のOwnership判定が必要になる

## Alternatives Considered

### 外部DLLを廃止し、すべてBuilt-in Backendへ移行する

採用しない。

これはLhaForge v2に近い設計となり、v1.7.xの目的であるv1系のModernizationとは異なる。

また、Legacy Formatや統合アーカイバDLLの利用環境を失う。

### 外部DLLを互換機能として残すがBuilt-in Backendを優先する

採用しない。

v1.xとしての動作を可能な限り維持するため、利用可能な外部DLLを第一候補とする。

Built-in BackendはFallbackおよび安全性・可用性確保のために利用する。

## Notes

外部DLL互換を維持することは、v1.6.7で対応していたすべてのDLLについて将来にわたり完全動作を保証することを意味しない。

個々のDLLについて、x64版の有無、Windows互換性、ライセンス、API互換性、安全性を調査し、Support Matrixとして管理する。
