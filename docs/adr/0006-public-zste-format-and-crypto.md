# ADR-0006: 公開ZSTE FormatとAuthenticated Encryptionを採用する

* Status: Accepted
* Target: LhaForge v1.7.x
* Related:

  * ADR-0004: Built-in BackendをFallbackとして持つ
  * `docs/design/v1.7.0/zste-format.md`
  * `docs/design/v1.7.0/backend.md`
  * `docs/design/v1.7.0/security.md`
  * `docs/design/v1.7.0/performance.md`

## Context

LhaForge v1.7.xではZstandardを主要なBuilt-in Backend対象として扱い、`.zst` / `.tar.zst`の圧縮・展開を正式対応対象とする。

一方、Zstandard Frame FormatそのものにはPassword-based Encryption機能がない。

`.zst`という拡張子のまま独自暗号Headerを付加すると、標準Zstandard Toolからは通常の`.zst`として扱えず、Formatと拡張子の期待が一致しない。

また、暗号FormatをLhaForge内部だけの非公開仕様にすると、次の問題がある。

* 第三者Softwareが互換実装しにくい
* Security Reviewが難しい
* 長期的なData Recovery性が低い
* LhaForgeのBinaryだけが唯一の復号手段になり得る
* FormatやSourceの秘匿をSecurity Boundaryとして誤認しやすい

## Decision

Zstandard圧縮StreamをPassword-based Authenticated Encryptionで保護する公開Container Formatとして、`ZSTE`を設計する。

名称はVendor-neutralに扱う。

```text
ZSTE = Zstandard Encrypted Container Format
```

LhaForgeは最初の実装およびReference Implementationとなるが、Format内部の識別子や仕様をLhaForge製品名へ依存させない。

初期拡張子は次とする。

```text
.zste
.tar.zste
```

`.zste`は単一Data Stream、`.tar.zste`は複数File / DirectoryをTAR化したStreamを対象とする。

`.zst` / `.tar.zst`は引き続き標準Zstandard Formatとして扱い、ZSTEとは混同しない。

## Public Specification and Source

次をPublic Repositoryで公開する。

* ZSTE Format Specification
* Encryption Source
* Decryption Source
* Parser / Writer Source
* Test Vectors
* Compatibility Fixtures
* Sample Archives suitable for testing

SecurityはFormatやSource Codeの秘密性へ依存させない。

秘密として扱うものはUser Password、Derived Key、Release Signing Private Key等のSecret Materialである。

公開SourceによりOffline Password Guessingの実装は容易になり得るが、公開Formatでは仕様だけから同等のAttack Toolを実装できる。Password Guessingへの防御はSource非公開ではなく、Argon2idのMemory / Time Costと十分に強いPasswordによって行う。

## Cryptographic Construction

ZSTE v1で採用するCryptographic Profileの基本方針を次とする。

```text
Password
   ↓
Argon2id v1.3
   ↓ 32-byte key
XChaCha20-Poly1305 secretstream-compatible authenticated stream
   ↑
Zstandard compressed payload
```

Authenticated Encryption / secure random / secure memoryのReference Implementationにはlibsodiumを第一候補として使用する。

Password KDFはLibrary固有の`ALG_DEFAULT`等へ依存せず、RFC 9106のArgon2id version 1.3と、その標準Parameter `m` (memory cost), `t` (time cost), `p` (parallelism / lanes)をWire Specificationで明示する。

libsodium high-level `crypto_pwhash(..., ALG_ARGON2ID13)`の現行実装は`p = 1`へ固定される一方、RFC 9106の一般推奨例は`p = 4`を用いる。この差をLhaForge固有仕様として早期固定しない。ZSTE v1では`p`を含むKDF ParameterをVendor-neutralに定義し、Default値とReference KDF LibraryはBenchmark / Security Review / Cross-implementation Test後、Wire Freeze前に確定する。

KDFのDefault Work Factorは実装前Benchmarkで決定する。Archiveには復号に必要なKDF Parameterを保存し、ReaderはFile由来Parameterを無制限に信用しない。

Cryptographyに将来の脆弱性が絶対に発生しないとは仮定しない。ZSTE v1のAlgorithm / Constructionを後から同じVersionのまま別方式へ読み替えず、重大な変更が必要な場合は新Format Versionとして明示し、既存Reader / Writerとの互換性を管理する。

## Header

ZSTE Headerは改ざん対策だけを目的としない。

少なくとも次の役割を持つ。

1. ZSTE Formatの識別
2. Format Versionの識別
3. KDF / Encryption / Compression方式の識別
4. Saltおよび復号に必要なParameterの保持
5. Stream初期化情報の保持
6. Future Versionでの安全な拡張

Headerは復号前にParseする必要があるため、Authentication前にSize / Count / KDF Resource Parameter等へHard Limitを適用する。

重要なHeader Byte列は暗号StreamのAuthenticated DataへBindingし、Passwordから正しいKeyが導出された後に改ざんを検出する。

Exact Magic、Byte Order、Record Framing、Header Length Encoding等のWire-level Detailは`zste-format.md`で設計し、Compatibility Test Vector生成前にFreezeする。

## Failure Policy

Authentication失敗、Wrong Password、Truncation、Corruption、Unsupported Version、Resource Limit違反ではFail Closedとする。

最終Authenticationが成功する前に、最終Output Pathへ不完全なPlaintextをCommitしない。

単一FileではTemporary OutputからCommit / Renameする。

`.tar.zste`では、認証前に最終DestinationへPartial Extractしない方式を別途PoCで確定する。

## Zstandard Profile

ZstdとZSTEは既定で同一Compression Profileを共有する。

Default Profile:

```text
Compression level: Ultra 22
Thread policy: Auto / Performance
Maximum compression (--max equivalent): OFF
```

`Ultra 22`はZstd CLIでいう`--ultra -22`相当のCompression Level選択を意味する。

`Auto / Performance`は「最大Thread数を無条件に使う」ことを意味しない。

> Compression Level 22を維持した上で、利用可能Hardwareを使って実際の処理時間を短縮する

ことを目的とし、Physical / Logical Core、Memory、Input Size、Storage等をBenchmarkしてHeuristicを確定する。

Zstd CLIの`--max`はLevel 23ではなく、最大Compressionを狙って複数Advanced Parameterを変更するPresetである。Defaultでは無効とし、Advanced Optionとして明示的に選択可能にする。

UIでは`--max`相当OptionにResource消費と処理時間、および展開側のMemory / Window Requirementが大きくなり得ることについて注意書きを表示するが、有効化時の確認Dialogは要求しない。

`.zst`と`.zste`は設定を共有するのをDefaultとするが、Userが共有を解除し、それぞれ独立Profileを設定できるConfiguration Modelを採用する。

## Interoperability

ZSTEはLhaForge専用Formatとして閉じない。

第三者実装がLhaForge Sourceを利用しなくても互換Reader / Writerを実装できるよう、次を要求する。

* Product名に依存しないWire Format
* AlgorithmをFunction NameではなくConstruction / exact parameter mappingとして記述
* All integer widths / byte order / length rulesを明記
* Unknown version / field handlingを明記
* Canonical Test Vectorsを公開
* Positive / Negative Test Casesを公開
* Reference ParserとFuzz対象を公開
* KDFの`m` / `t` / `p`を含むExact Parameter Mappingを公開
* Secretstream互換Record LayerのExact Byte RuleとCanonical Test Vectorを公開

他Softwareが対応した場合、相互にCreate / ExtractできることをCompatibility Goalとする。

## Consequences

### Positive

* `.zst`の標準互換性を壊さず暗号化Zstandardを提供できる
* Authenticated EncryptionによりConfidentialityとIntegrityを同時に扱える
* Public Specificationにより第三者実装が可能
* Encryption / Decryption SourceをSecurity Reviewできる
* Test VectorによりCross-implementation Compatibilityを検証できる

### Negative

* 新規Formatの長期Maintenance責任が発生する
* Password KDF / Header / Record FramingのSecurity Reviewが必要
* 初期状態では一般的なArchive SoftwareがZSTEを扱えない
* Compatibilityを壊さないVersioning Policyが必要
* KDF ParameterによるDoS対策が必須

## References

* Zstandard: https://github.com/facebook/zstd
* Zstandard Format: https://datatracker.ietf.org/doc/html/rfc8878
* Zstd CLI manual: https://github.com/facebook/zstd/blob/dev/programs/zstd.1.md
* Argon2: https://www.rfc-editor.org/rfc/rfc9106.html
* libsodium secretstream: https://doc.libsodium.org/secret-key_cryptography/secretstream
* libsodium password hashing: https://doc.libsodium.org/password_hashing/default_phf
* Argon2 reference implementation: https://github.com/P-H-C/phc-winner-argon2
* libsodium memory management: https://doc.libsodium.org/memory_management
