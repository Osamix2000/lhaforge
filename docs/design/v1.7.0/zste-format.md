# ZSTE v1 Format Design

- Status: Draft / pre-wire-freeze
- Target: LhaForge v1.7.x
- Format name: Zstandard Encrypted Container Format
- Extensions: `.zste`, `.tar.zste`
- Related ADR: `docs/adr/0006-public-zste-format-and-crypto.md`

## 1. Purpose

ZSTEはZstandard CompressionとPassword-based Authenticated Encryptionを組み合わせる公開Container Formatである。

LhaForgeが最初のReference Implementationとなるが、他Softwareが独立してReader / Writerを実装できることを設計要件とする。

このDocumentはArchitecture-level Invariantを先に固定する。Magic Byte、Field Offset、Record Framing等のBinary Wire Layoutは、Prototype / Fuzz / Cross-implementation Testの準備後にFreezeする。

Wire Layout Freeze前に生成した`.zste`はCompatibility保証対象にしない。

## 2. Format Roles

```text
.zst
  Standard Zstandard stream

.tar.zst
  TAR stream -> Standard Zstandard

.zste
  Data stream -> Zstandard -> ZSTE authenticated encryption

.tar.zste
  TAR stream -> Zstandard -> ZSTE authenticated encryption
```

ZSTEはZIPのようなMulti-entry Archive Directoryを独自に持たない。

複数File / Directoryを一つにまとめる場合はTARをContainer Layerとして使用する。

## 3. Vendor-neutral Identity

Format内部のIdentityを`LhaForgeZSTE`等のProduct固有名へ固定しない。

Wire FormatにはZSTE自体を識別するMagicとVersionを持たせる。

Exact Magic Byte列はCollision RiskとParser Robustnessを確認してWire Freeze時に決定する。

拡張子`.zste`は現段階の採用案とする。2026-08-08時点の一般Web / Repository検索では、広く定着したArchive / File Formatとして`.zste`を使用する有力な例は確認できず、IANA Media Type Registryにも`zste` subtypeは登録されていない。ただし「世界中で未使用」を証明するものではないため、Release Candidate前にFile Extension / MIME衝突を再調査する。

MIME TypeはFormat安定後に検討し、初期段階でVendor固有MIMEへ固定しない。

## 4. Cryptographic Profile

ZSTE v1で許容するCryptographic Profileは原則1つに固定する。

```text
KDF:
  Argon2id version 1.3

Derived key:
  256 bit

Authenticated encryption stream:
  XChaCha20-Poly1305 secretstream-compatible construction

Compression:
  Zstandard
```

`algorithm = default`のようにLibrary Versionで意味が変わる指定はWire Formatへ使用しない。

将来AlgorithmやConstructionに重大なSecurity問題が見つかった場合、ZSTE v1の意味をSilentに変更せず、新しいFormat Version / Profileとして移行する。ReaderはVersionごとのExact Ruleを維持する。

Authenticated Encryption側のReference Implementationにはlibsodiumを第一候補として利用する。ただしFormat仕様はlibsodium API Callそのものではなく、Algorithm / Encoding / Framing / Authentication Ruleとして記述する。

## 5. Password KDF

Passwordから直接Encryption Keyを作らない。

```text
Password + random salt + KDF parameters
                ↓
          Argon2id v1.3
                ↓
          32-byte secret key
```

ZSTE v1のWire SpecificationではLibrary固有の`opslimit` / `memlimit`名ではなく、RFC 9106 / Argon2の標準Parameterを直接定義する。

```text
Argon2 type: Argon2id
Argon2 version: 1.3 (v=19)
Output: 32 bytes
m: memory cost in KiB
t: time cost / iterations
p: parallelism / lanes
Salt: random bytes (exact length is fixed at Wire Freeze)
```

ここは今回のReviewで訂正した点である。libsodium high-level `crypto_pwhash(..., ALG_ARGON2ID13)`の現行実装は内部で`p = 1`を使用するが、RFC 9106の一般推奨Profileは`p = 4`を使用する。Vendor-neutralな公開Formatを特定Libraryのhigh-level API制約へ早期固定しない。

したがって、`m` / `t` / `p`はWire Format上で明示し、Default値はBenchmark / Security Review / Cross-implementation Testを通してWire Freeze前に決定する。Reference KDF実装にはこれらを明示指定できるArgon2id implementationを使用する。公式Argon2 reference implementationは有力候補である。

Headerへ保存するKDF情報の最小候補:

```text
KDF identifier
Argon2 version
Salt
memory cost (m)
time cost (t)
parallelism / lanes (p)
```

Default KDF Costは未確定である。

実装対象Windows MachineでUnlock LatencyとPassword Guessing ResistanceをBenchmarkし、Defaultを決定する。

ReaderはHeaderに書かれた値をそのままAllocation / KDFへ渡さず、Implementation Hard LimitとUser Policyを先に適用する。

## 6. Encryption Stream

Zstandardから出力されたByte Streamを、XChaCha20-Poly1305 Secretstream-compatible Layerへ流す。ZSTE v1ではlibsodium secretstreamとのBinary Interoperabilityを目標とするが、Exact Record Construction / Rekey Rule / Byte EncodingはWire Freeze前に仕様とCanonical Test Vectorで固定する。

```text
Input
  ↓
Zstandard streaming compressor
  ↓
Bounded plaintext chunks
  ↓
Authenticated encryption stream
  ↓
ZSTE records
```

Decryptionは逆方向とする。

```text
ZSTE records
  ↓
Authenticate + decrypt
  ↓
Zstandard streaming decompressor
  ↓
Temporary / staged plaintext output
```

最終Recordは明示的なFinal Tagを持ち、EOFだけを正常終了条件にしない。

Truncation、Record deletion、reordering、duplication、modificationをAuthentication failureとして扱う。

## 7. Header Responsibilities

Headerは次の役割を持つ。

```text
Format identification
Format version
Header length / structural information
KDF identifier and parameters
Salt
Encryption construction identifier
Compression identifier
Encryption stream initialization information
Future-compatible flags / reserved fields
```

元FileのFull Path、Windows User名、Password Hint等の不要なPrivacy-sensitive Metadataを平文Headerへ保存しない。

Compression Level、Thread Count、`--max`等はDecodeに必要な情報ではないため、ZSTE v1の必須Header Fieldにはしない。

## 8. Header Authentication

Headerは復号処理を開始するために平文でParseする必要がある。

このため、処理順序は次とする。

```text
Read bounded fixed prefix
  ↓
Validate magic / version / lengths
  ↓
Validate KDF parameters against hard limits
  ↓
Derive key using Argon2id
  ↓
Initialize authenticated stream
  ↓
Process the first encrypted record with canonical immutable header bytes bound as associated data
  ↓
Only after successful record authentication, treat the header as authenticated metadata
  ↓
Process remaining encrypted records
```

Authentication前のValidationはDoS / Integer Overflow / excessive allocation対策であり、Cryptographic Authenticityを意味しない。

SecretstreamにはHeaderだけを単独で認証する別Operationがあるわけではないため、Canonical Header Byte列をEncrypted RecordのAssociated DataへBindingして認証する。少なくとも最初のRecordでこのBindingを必須とし、空Payloadでも認証可能なFinal Recordを必ず生成する方向とする。

Key導出後、HeaderをBindingしたRecordのAuthenticationが成功して初めて、Header内容をAuthenticated Metadataとして扱う。

Exact associated-data binding rule、空Payload時のRecord Rule、Headerを全Recordへ繰り返しBindingするかはWire Freeze時に固定する。

## 9. Resource Exhaustion / DoS

Untrusted ZSTE Fileは、Authentication前から攻撃Inputとして扱う。

最低限のParser Requirement:

* Maximum header size
* Minimum / maximum supported version
* Integer overflow checks
* Reserved bits validation
* Bounded KDF memory cost
* Bounded KDF time cost
* Bounded KDF parallelism / lanes
* Bounded record size
* Bounded internal buffer size
* No allocation directly from unchecked file length
* Unknown algorithm / mandatory field -> reject

KDF hard limitは「Writerが作れる最大値」と「Readerが自動受理する最大値」を分離できる設計とする。

## 10. Password and Key Memory

Plaintext PasswordとDerived Keyは必要以上にMemoryへ保持しない。

Reference Implementationでは可能な範囲でlibsodiumのSecure Memory APIを使用する。

```text
sodium_mlock / protected allocation where practical
sodium_memzero / sodium_munlock after use
no password or key in log
no password in crash diagnostic text
```

Memory LockはOS制限等で失敗し得るため、成功を絶対前提にせず、Zeroizationは独立して実施する。

## 11. Output Commit Policy

Authentication失敗時に不完全なPlaintextを正規Outputとして残さない。

### `.zste`

単一FileはTemporary Fileへ書き、Final Authentication成功後にDestinationへCommit / Renameする。

### `.tar.zste`

Directory / Multi-file extractionでは、次の候補をPoCで比較する。

1. 認証済みTemporary TARを生成後にExtract
2. Isolated staging directoryへ展開し、Final Authentication後にCommit

Security、Disk Usage、Performance、Recoveryを比較して最終方式を決定する。

## 12. Zstandard Compression Profile

ZSTEの暗号有無によってZstandard Compression Levelを下げない。

Default Profile:

```text
Compression level: 22 (Ultra)
Thread policy: Auto / Performance
Maximum compression preset: OFF
```

Level 22はZstd CLIでいう`--ultra -22`相当である。

`Auto / Performance`はWorker数最大化そのものではなく、Level 22を維持しながらWall-clock timeを短縮するPolicyである。

Zstdのparallel compressionではWorker数とMemory Usageが増加し、Job overlapはCompression RatioとSpeedのTrade-offを持つ。そのためPhysical Core数を初期Baselineとし、Logical Processor、Input Size、Memory、Storage等をBenchmarkしてHeuristicを決定する。

`--adapt`はCompression Level自体を動的変更するため、Level 22固定というDefault思想には使用しない。

## 13. Maximum Compression Mode

Zstd CLIの`--max`はCompression Level 23ではない。

複数のAdvanced Compression Parameterを最大Compression方向へ設定するCLI Presetであり、Zstd v1.5.7 Releaseでは`--ultra -22`より大幅に時間・Memoryを使うことが明記されている。

ZSTE / Zstd SettingsではAdvanced Optionとして提供する。

```text
[ ] Maximum compression (--max equivalent)
```

Default: OFF

UIではResource消費と処理時間について常時注意書きを表示する。Enable時のConfirmation Dialogは設けない。

Built-in Backendでは「Level 23」として実装せず、Pinned Zstd Versionに対する`--max`相当Presetとして扱う。Dependency更新時にPreset内容が変わる可能性があるため、Benchmark / Regression対象とする。

`--max`を使用して生成したPayloadも標準Zstandard Frameであり、Decoderが`--max`というCreate-side Option自体を知る必要はない。ただし`--max`は大きなWindow等を選択し得るため、Frameが要求するDecompression Memory / Window Limitが通常Profileより大幅に増える可能性がある。LhaForgeはHeaderから必要Resourceを事前評価し、User / System Policyを超える場合は安全に拒否または明示的に許可する。第三者DecoderでもDefault Memory Limitによって拒否される可能性があるため、Advanced OptionのCompatibility Noteへ含める。

## 14. Shared and Independent Profiles

Defaultでは`.zst`と`.zste`が同一Profileを使用する。

概念設定:

```text
[x] Use the same Zstandard compression profile for .zst and .zste
```

共有を解除した場合は独立設定を持つ。

```text
.zst profile
  level
  thread policy
  maximum compression
  other future Zstd settings

.zste profile
  level
  thread policy
  maximum compression
  other future Zstd settings
```

`.tar.zst`は`.zst` Profile、`.tar.zste`は`.zste` Profileを継承する。

UI Layout / wordingは後段のUI Designで確定する。

## 15. Interoperability Requirements

公開仕様として次を必須とする。

* Exact magic bytes
* Integer byte order
* Field widths
* Header length rules
* KDF exact mapping
* Encryption stream exact construction
* Record framing
* Final record rules
* Associated data rules
* Error handling for unknown versions / fields
* Resource-limit recommendations
* Canonical writer test vectors
* Canonical reader test vectors
* Corruption / truncation negative vectors

LhaForge以外の実装が同じTest VectorをPassできることをZSTE v1 Freeze条件とする。

## 16. Source Publication

Encryption / Decryption双方のSourceを公開する。

SecurityはSource Secretに依存させない。

RepositoryへCommitしてはいけないもの:

* Real user passwords
* Derived keys captured from real data
* Signing private keys
* Credential / token / secret environment files

Publicにしてよいもの:

* Format specification
* Reference encryption/decryption source
* Synthetic test passwords
* Deterministic test vectors created solely for interoperability testing
* Sample encrypted fixtures that contain no real secret data

## 17. Wire Freeze Gate

ZSTE v1のBinary FormatをFreezeする前に次を完了する。

1. Extension collision recheck
2. Threat model review
3. Parser resource-limit review
4. KDF default benchmark
5. Record framing PoC
6. Wrong-password / corruption / truncation tests
7. Fuzz target
8. Canonical test vectors
9. Independent minimal decoder or second implementation test
10. License / third-party notice review

## 18. Open Items

* Exact magic bytes
* Fixed prefix layout
* Header byte order
* Record length encoding
* Default encrypted chunk size
* Default Argon2id `m` / `t` / `p`
* Reader KDF `m` / `t` / `p` hard maximums
* `.tar.zste` authenticated extraction staging method
* MIME registration / provisional media type
* Format specification location if separated from LhaForge repository
* Independent reference CLIの要否
* Standard `.zst` frame checksum default policy (CLI default and libzstd API default differ)

## References

* https://github.com/facebook/zstd
* https://github.com/facebook/zstd/releases/tag/v1.5.7
* https://github.com/facebook/zstd/blob/dev/programs/zstd.1.md
* https://facebook.github.io/zstd/doc/api_manual_v1.5.7.html
* https://www.rfc-editor.org/rfc/rfc8878.html
* https://www.rfc-editor.org/rfc/rfc9106.html
* https://www.iana.org/assignments/media-types/media-types.xhtml
* https://doc.libsodium.org/password_hashing/default_phf
* https://github.com/P-H-C/phc-winner-argon2
* https://doc.libsodium.org/secret-key_cryptography/secretstream
* https://doc.libsodium.org/memory_management
