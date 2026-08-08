# LhaForge v1.7.0 Security Design

* Status: Draft
* Target: LhaForge v1.7.x
* Scope: Main Application / External Backend / LegacyHost / Built-in Backend / Installer / Updater / Shell Integration

## 1. Principle

LhaForge v1.7.xでは、Legacy Compatibilityの維持を理由に既知の危険な実装をそのまま継承しない。

コード署名の採用有無とは独立して、SecurityをArchitectureの必須要件として扱う。

基本原則:

* Least Privilege
* Untrusted Inputを信用しない
* Fail Safe
* 明示的なTrust Boundary
* Security Validationの共通化
* Resource Usageの上限管理
* 安全でないFallbackを行わない
* Sensitive DataをLogへ出さない
* Securityのための処理はPerformance設計と両立させる

## 2. Primary Threat Sources

主な入力・境界をUntrustedとして扱う。

* Archive File / Entry Metadata
* Archive Entry Path
* External Archive DLL
* Legacy DLLの戻り値
* Drag & Drop / Shellから渡されるPath
* Command Line
* Configuration File
* Downloaded Update / Package
* LFCaldix由来File
* IPC Message
* Symlink / Junction / Reparse Point

## 3. Extraction Path Security

Archive EntryのPathをそのままFilesystem Pathへ結合しない。

検証対象:

* `..` / Path Traversal
* Absolute Path
* Drive-qualified Path
* UNC Path
* Device Namespace
* NTFS ADS
* Reserved Device Name
* Trailing Dot / Space
* Empty / Dot Path
* Path Length / Component Length
* Unicode Control / Confusable Character
* Symlink / Junction / Reparse Point

CanonicalizationとContainment Checkを行い、最終Outputが意図したExtraction Rootの外へ出ないことを確認する。

String prefix比較だけに依存しない。

## 4. Reparse Point and TOCTOU

検証時点では安全でも、書込みまでの間にDirectoryがSymlink / Junction等へ変更される可能性を考慮する。

可能な範囲でHandleベースの検証、Reparse Point確認、既存Pathの再検証を行う。

完全な防止方式はWindows API設計とPoC後に確定する。

## 5. Archive Bomb / Resource Exhaustion

異常に大きい展開サイズ、File数、Compression Ratio、深いDirectory、巨大Metadata等によるResource Exhaustionを考慮する。

Budget候補:

* Total uncompressed size
* Single entry size
* Entry count
* Compression ratio
* Nested archive depth（将来自動再帰処理を行う場合）
* Memory allocation
* Temporary disk usage
* Operation time / stall detection

固定値だけでは正当な巨大Archiveを阻害するため、Default安全値、警告、ユーザー明示許可等を組み合わせる。

## 6. Compression Input Security

圧縮対象はOperation Plannerで確定する。

`.git`、`.env`等のSensitive / Unwanted File除外は誤共有防止機能として提供する。

ただしFile名だけでSecretを完全検出できるとはみなさない。

除外有効時にBackendが独自再Scanして除外対象を追加しないよう、`ExactInputSet` Capabilityを要求する。

## 7. DLL Loading

External DLLは明示的なTrust Boundaryとする。

* Absolute Pathを使用する
* DLL Search Pathを制限する
* PE Architectureを事前確認する
* Required Exportを確認する
* API / Version / Capabilityを確認する
* Unexpected dependency loadingを可能な範囲で制限する
* DLL PathをCurrent Directoryへ依存させない

外部DLL互換を維持することは、安全でないDLLを無条件にロードすることを意味しない。

## 8. LegacyHost / IPC

LegacyHostはSandboxとはみなさないが、Process Boundaryとして利用する。

* Named Pipe相手をValidationする
* Message sizeを制限する
* Protocol Versionを持つ
* Length / Count / Enum値を検証する
* PathやOptionを信用しない
* Crash / Timeoutを本体へ伝播させず処理する
* Archive DataそのものをIPCで転送しない

## 9. Temporary Files

Temporary Directoryは予測可能な固定名だけに依存しない。

* Unique working directory
* 適切なACL
* Collision回避
* Cleanup
* Crash後のRecovery / stale temp処理
* Symlink / Reparse Point対策

Sensitive Dataを含む可能性があるTemporary Fileの残留を考慮する。

## 10. Installer / Update / Elevated Components

通常処理は非昇格とし、System-wide変更だけをElevationする。

Elevated Componentを起動する際は、可能な範囲で次を確認する。

* Expected Path
* Package Manifest
* Component Version / Architecture
* Hash
* Authenticode Signature（存在する場合）

Original Setup.exeをRoutine OperationのTrust Anchorにはしない。

Updateは既存Installを変更する前にDownload Artifactを検証する。

## 11. Configuration

Configuration FileをUntrusted InputとしてParseする。

* Size limit
* Invalid encoding handling
* Integer / Enum range validation
* Path validation
* Unknown key handling
* Corrupt config fallback

Legacy Compatibility ReaderとCurrent Configurationを分離し、古い値を無条件に内部状態へ反映しない。

## 12. Logging and Sensitive Data

Logへ次を不用意に出力しない。

* Password
* Encryption key
* Token
* Environment secret
* Private key content
* Credential

Full PathやFile NameもSensitiveになり得るため、Operational Logでは必要性を考慮する。

Debug / TraceでもSecret内容そのものは記録しない。

## 13. Compiler / Platform Mitigations

Modern Build環境へ移行後、Windows / MSVCが提供するMitigationを利用する方向で検証する。

候補:

* ASLR
* DEP / NX
* Stack protection
* Control Flow Guard
* High Entropy VA
* CET compatibility（対象環境・Toolchainが許す場合）

Legacy Compatibilityへの影響を確認しながら有効化する。

## 14. Memory / Integer Safety

Archive Metadataには外部入力由来のSize / Countが多いため、Integer Overflow、Allocation Overflow、Index Validationを重視する。

* Size calculationのOverflow Check
* Bounded allocation
* Container size validation
* Signed / Unsigned conversion確認
* Null / lifetime management

Modern C++への段階的移行でRAII等を活用する。

## 15. Testing

Security Regression Testを通常の互換性Testと分離しない。

Test候補:

* Zip Slip / Traversal Archive
* Absolute Path Entry
* ADS Entry
* Reserved Name
* Reparse Point scenario
* Huge Entry Count
* Extreme Compression Ratio
* Corrupt Header / Truncated Archive
* ZSTE invalid / oversized KDF parameters
* ZSTE wrong password / modified authenticated header
* ZSTE record removal / reorder / duplicate / truncation
* Malformed Unicode
* DLL architecture mismatch
* Invalid IPC payload
* Corrupt configuration

将来的にParser / Security BoundaryにFuzz Testingを導入できる構造を検討する。

## 16. ZSTE Cryptographic Security

ZSTE v1はFormat / Source Codeの秘匿をSecurity Boundaryとしない。

Publicにするもの:

* Format Specification
* Encryption Source
* Decryption Source
* Parser / Writer Source
* Test Vectors
* Synthetic Compatibility Fixtures

Secretとして扱うもの:

* User Password
* Derived Encryption Key
* Release Signing Private Key
* Real Credential / Token

Password-based EncryptionではArchive Fileを入手したAttack者がOffline Password Guessingを行えることを前提とする。Source Code非公開化でこれを防ごうとせず、Argon2id v1.3のMemory / Time Cost、Password Strength、Secure Key Handlingで対策する。

Password KDFはArgon2id v1.3を明示し、Wire Specificationでは`m` / `t` / `p`をLibrary固有APIから独立して定義する。libsodium high-level `crypto_pwhash()`の現行`p = 1`制約へFormatを早期固定しない。Authenticated Encryption / secure random / secure memory側はlibsodiumを第一候補とする。`ALG_DEFAULT`のようにLibrary Versionで意味が変わる値をZSTE v1のWire Requirementには使用しない。

Authenticated EncryptionはXChaCha20-Poly1305 secretstream-compatible constructionを用い、次を検出対象とする。

* Ciphertext modification
* Record truncation
* Record removal
* Record reordering
* Record duplication
* Premature EOF
* Missing final tag
* Authenticated Header modification

### Header pre-authentication validation

Header AuthenticationにはPasswordからDerived Keyを作る必要がある。そのためAuthentication前にUntrusted HeaderをParseする段階が存在する。

この段階では最低限、

* Fixed prefix size
* Header maximum length
* Version range
* Integer overflow
* KDF memory hard limit
* KDF time cost hard limit
* KDF parallelism / lanes hard limit
* Record length hard limit
* Unknown mandatory algorithm / field

を検査し、危険な値ではArgon2idや巨大Allocationを開始しない。

### Password / key memory

Plaintext PasswordとDerived Keyは必要以上に保持しない。

Reference Implementationでは`libsodium`のSecure Memory機能を利用できる範囲で使用し、使用後のZeroizationを必須とする。Memory LockはOS Limit等で失敗し得るため、失敗時のPolicyを明示し、Lock成功だけにSecurityを依存させない。

Password / Derived KeyをLog、Crash message、Telemetryへ出力しない。

### Output commit

Wrong Password / Authentication failure / Corruption時に不完全なPlaintextを正規Destinationへ残さない。

`.zste`はTemporary Outputへ書き、Final Authentication成功後にCommitする。

`.tar.zste`は認証前に最終DestinationへPartial Extractしない。Temporary TARまたはIsolated staging directory方式をPoCで決定する。

詳細は`zste-format.md`およびADR-0006を参照する。

---

## 17. Open Items

* Windows Path Canonicalization APIの最終方式
* Reparse Point / TOCTOU防御の実装詳細
* Archive Bomb Default Budget
* External DLL Trust / Warning Policy
* Update Manifest形式
* Fuzzing対象
* ZSTE KDF `m` / `t` / `p` default / reader hard resource limits
* ZSTE Wire Format independent implementation review
* Minimum Windows Versionに応じたMitigation設定
