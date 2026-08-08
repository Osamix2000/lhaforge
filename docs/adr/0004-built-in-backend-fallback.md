# ADR-0004: Built-in BackendをFallbackとして持つ

* Status: Accepted
* Target: LhaForge v1.7.x
* Related:

  * ADR-0002: v1系外部DLL互換を維持する
  * ADR-0003: x64本体とLegacyHostを採用する
  * ADR-0006: 公開ZSTE FormatとAuthenticated Encryptionを採用する

## Context

LhaForge v1.xは外部アーカイバDLLを中心にArchive処理を行う。

しかし、外部DLLだけに依存すると次の問題がある。

* DLLがインストールされていない
* DLLが古い
* 現代Windowsで動作しない
* x64版が存在しない
* DLLロードに失敗する
* 必要なCapabilityを持たない
* ユーザーが誤ったDLLへ差し替える
* 外部配布元が将来利用できなくなる

実際にv1.6.7環境では、古い7-ZIP32.DLLによってArchive展開に失敗し、DLLのみを新しい互換版へ交換することで正常動作した事例が確認されている。

v1.7.xでは外部DLL互換を維持する一方、LhaForge単体でも主要Archive形式を最低限扱える可用性が必要である。

## Decision

LhaForge v1.7.xにはBuilt-in Archive Backendを搭載する。

ただし、Built-in Backendはv1系外部DLL文化を置き換えるものではない。

通常の優先順位は次の通りとする。

1. x64外部DLL
2. x86外部DLL + LegacyHost
3. Built-in Backend
4. Error

Built-in Backendは主としてFallback、基本機能保証、安全な代替経路として利用する。

## Initial Scope

最低限、Built-in Backendで次の形式を扱えることを目標とする。

### ZIP

* List
* Test
* Extract
* Create
* 必要に応じてUpdate

### 7z

* List
* Test
* Extract
* Createを可能な範囲で対応

### TAR

* List
* Test
* Extract
* Create

### gzip

対象:

```text
.gz
.tar.gz
.tgz
```

圧縮・展開に対応する。

### bzip2

対象:

```text
.bz2
.tar.bz2
.tbz
.tbz2
```

圧縮・展開に対応する。

### XZ

対象:

```text
.xz
.tar.xz
.txz
```

圧縮・展開に対応する。

### LZMA

```text
.lzma
```

圧縮・展開に対応する。

### Zstandard / ZSTE

標準Zstandard対象:

```text
.zst
.tar.zst
```

圧縮・展開に対応する。

Authenticated Encryption対象:

```text
.zste
.tar.zste
```

ZSTEは公開・Vendor-neutralなFormatとして設計し、LhaForge Built-in BackendをReference Implementationとする。Cryptographic / Wire Format方針はADR-0006および`docs/design/v1.7.0/zste-format.md`で定義する。

### RAR / RAR5

Built-in Backendでは、

* List
* Test
* Extract

を対象とする。

RAR Archiveの作成は対象外とする。

RAR作成が必要な場合は、利用可能なExternal Backendに委ねる。

## Implementation Direction

Built-in BackendはApplication Logicと直接密結合させない。

External Backendと同様に、共通Archive Backend Interfaceを通して利用する。

```text
Archive Manager
      │
      ├─ External DLL Backend
      │
      ├─ Legacy DLL Backend
      │
      └─ Built-in Backend
```

LhaForge側はBackendの実装方式ではなくCapabilityを見て操作を選択する。

Built-in Backendの内部実装には、複数Archive形式を安全に扱えるライブラリ群を利用する。

libarchiveを中心とした構成は有力候補とするが、具体的なLibrary選定は別途設計・ライセンス・機能・性能評価を行う。

依存Libraryは可能な限りStatic Linkまたは明確にLhaForge管理下へ置き、External DLL BackendとはOwnershipを分離する。

## Fallback

External Backendが利用できない場合、必要なCapabilityをBuilt-in Backendが持っていればFallbackする。

例:

```text
7-ZIP64.DLL
    ↓ Load失敗

7-ZIP32.DLL
    ↓ 存在しない

Built-in
    ↓

ZIP展開継続
```

ただしOperation開始後の自動Fallbackは慎重に扱う。

例えばExtract途中でExternal Backendが失敗した場合、

```text
一部ファイル生成済み
↓
Built-inで最初から再実行
```

すると既存ファイル処理や副作用が発生する。

そのため、Fallbackは原則としてOperation開始前のBackend Selection段階で行う。

Operation開始後に障害が発生した場合は、操作内容・出力状態を確認した上で、明示的な再試行を行う。

## Safe Mode

将来的に、安全性確認や障害切り分けのため、

```text
/safe
```

等のModeを設けることを許容する。

Safe Modeでは、

```text
External DLL
LegacyHost
```

を利用せず、Built-in Backendのみを使用する。

これにより、

* 外部DLL障害の切り分け
* 不明なDLLを利用したくない環境
* 最低限のArchive操作

を提供できる。

Safe Modeの具体的なCLI/UI仕様は別途決定する。

## Security

Built-in Backendであっても、Archive Libraryが返すFile PathやMetadataを信頼してはならない。

External Backendと共通のSecurity Layerを通す。

例:

* `../` Path Traversal
* Absolute Path
* Drive Path
* UNC Path
* Device Path
* NTFS ADS
* Reserved Device Name
* Trailing Dot / Space
* Symlink
* Junction
* Reparse Point
* Unicode Control Character
* Resource Exhaustion
* Archive Bomb

Backendごとに個別のPath Securityを実装するのではなく、可能な限りLhaForge共通Security Policyへ集約する。

## Compatibility

Built-in Backendによる処理結果がExternal Backendと完全に一致するとは限らない。

差異が発生し得る項目:

* Timestamp
* File Attribute
* Unicode Filename
* Password
* Encryption Method
* Compression Method
* Archive Comment
* Extended Metadata
* Symbolic Link
* Permission
* MultiVolume

そのため、BackendごとにCapabilityおよびCompatibility情報を管理する。

Built-in Backendが対応している形式であっても、必要なCapabilityを満たさない場合はExternal Backendを選択する。

## Logging

Backend選択理由をDebug Logへ記録する。

例:

```text
Archive format: ZIP
Requested operation: Extract

7-ZIP64.DLL:
  Loadable: No

7-ZIP32.DLL:
  Available: No

Built-in ZIP:
  Extract: Supported

Selected backend:
  Built-in ZIP
```

Warning以上は異常時に使用し、通常のFallback理由を過剰にWindows Event Logへ出力しない。

## Consequences

### Positive

* 外部DLLがなくても主要形式を扱える
* 古いDLL障害の影響を減らせる
* 新規インストール直後でも基本Archive機能を提供できる
* 外部配布元への依存を軽減できる
* Safe Modeを実現できる
* x86 Legacy DLL依存を段階的に減らせる

### Negative

* LhaForge自身がArchive Libraryを管理する必要がある
* Binary Sizeが増える
* Library Update対応が必要になる
* External Backendとの差異を検証する必要がある
* 複数Backend間のCapability管理が必要になる

## Alternatives Considered

### Built-in Backendを持たずExternal DLLのみ利用する

採用しない。

v1系の構造には最も近いが、現代のApplicationとして可用性が低い。

### Built-in Backendのみ利用する

採用しない。

v1系外部DLL互換を失い、LhaForge v2に近い設計となる。

### Built-in Backendを常に最優先する

採用しない。

v1.xの外部DLL運用を継承する方針に反する。

## Notes

Built-in Backendの目的は「外部DLLをなくすこと」ではなく、

```text
External DLLの互換性
+
LhaForge単体としての基本可用性
```

を両立することである。

将来Backendの品質・安全性・互換性が変化した場合、優先順位については別ADRで再検討できる。
