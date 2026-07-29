# LhaForge v1.7.0 Encoding Design

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7 (`ver_1_6_7`)
- Development branch: `develop-v1.7.0`
- Scope: Application内部文字列、Archive Metadata、Legacy DLL境界、設定、Log、Installer Metadata、Repository Text

Related documents:

- `architecture.md`
- `archive-operations.md`
- `backend.md`
- `security.md`
- `performance.md`
- `logging.md`
- `migration.md`
- `installer.md`

---

## 1. Purpose

LhaForge v1.7.xでは、v1.6.7が持つCP932 / Shift_JIS時代のCompatibilityを維持しながら、Application内部と新規管理DataをUnicode中心へ移行する。

Encoding Modernizationの目的は、単にすべてのFileをUTF-8へ変換することではない。

次を同時に満たすことを目的とする。

1. 現代Windows上でUnicode File Nameを正しく扱う。
2. Legacy Archive DLLのANSI / CP932 APIを継続利用できる。
3. 既存`LhaForge.ini`、`LFCaldix.ini`、`cldx`等を破壊しない。
4. 新しいLhaForge管理TextのEncodingを明確化する。
5. 変換不能文字を黙って`?`等へ置換しない。
6. Archiveから展開したUser File Contentsを勝手に変換しない。
7. Encoding処理をSecurity / Performance上の弱点にしない。
8. Repository上でも文字化けしたFile Nameや壊れたLinkを再発させにくくする。

---

## 2. Core Principles

### 2.1 Unicode first

Application内部の論理的なText ModelはUnicodeとする。

Windows APIとの境界ではWide Character APIを優先し、Win32 Native RepresentationとしてUTF-16を利用する。

```text
UI / Configuration / Operation Planner
             │
             │ Unicode
             ▼
       Application Core
             │
       ┌─────┴────────────┐
       ▼                  ▼
Wide Win32 API       Backend Adapter
                          │
                          ├─ Unicode API
                          └─ Legacy ANSI / CP932 API
```

System ANSI Code Pageへ暗黙依存する処理はLegacy Boundary以外へ広げない。

### 2.2 Convert only at boundaries

UTF-16 / UTF-8 / CP932等の変換は、必要なBoundaryで明示的に行う。

```text
Internal Unicode
      ↓
Explicit Encoding Boundary
      ↓
External Format / Legacy API
```

Application内部で「現在このStringはCP932なのかUTF-8なのか」が不明な状態を作らない。

### 2.3 No silent lossy conversion

変換不能文字を`?`、代替文字、Best-fit Character等へ黙って置換して処理を継続しない。

Lossy Conversionが発生する場合は、少なくとも次のいずれかとする。

- Operation開始前に別BackendへFallbackする
- UserへCompatibility上の制限を通知する
- Operationを安全に中止する

Display専用の代替表示と、実際のFile Name / Archive Entry Nameとして利用する値は区別する。

### 2.4 Preserve user payload

LhaForgeはArchiveから展開したUser File ContentsのEncodingや改行を変更しない。

```text
Archive Entry Data
      ↓
Extract
      ↓
Original bytes
```

Text Fileらしく見えることを理由にUTF-8化、BOM追加、改行変換等を行わない。

### 2.5 Legacy data is data, not migration debris

CP932等で保存されたLegacy Configuration / Documentationを「古いから」という理由だけで変換しない。

Migration時は元Byte列をBackup / Preserveし、互換性が確認できたDataだけSchema-awareに移行する。

---

## 3. Internal String Model

v1.7.x Application CoreではUnicode Stringを利用する。

Windows上では、次を基本とする。

- File Path: UTF-16 / Wide Win32 API
- Window Text: UTF-16
- Command Line: Wide Character Command Line
- Registry String: Wide API
- Shell Integration: Wide API
- Internal Logical Text: Unicode

C++上の具体的なString Type、Wrapper、UTF LibraryはBuild Modernization時に確定する。

重要なのは、Application CoreがSystem ACPやLocale依存の`char*`をDefault Text Modelにしないことである。

---

## 4. New First-party Text Policy

LhaForge v1.7.xが新規に所有するText Fileは、特別なCompatibility要件がない限りUTF-8をDefaultとする。

### 4.1 Default Encoding

新規LhaForge管理TextのDefault:

```text
UTF-8 without BOM
```

理由:

- 現代Toolとの互換性
- Git / GitHubとの相性
- ASCII互換
- Encoding識別が明確
- UTF-16よりText Toolで扱いやすい

UTF-8 BOM付きFileはRead可能とするが、新規書き込みのDefaultにはしない。

### 4.2 Machine-readable text

将来Package Manifest、Install State、Journal等をJSONその他のText Formatで定義する場合は、Format Specificationと矛盾しない範囲でUTF-8 BOMなしを基本とする。

署名・Hash・再現可能Build等へ利用するMachine-readable Fileでは、SerializationをCanonical化し、OS LocaleによりByte列が変化しないようにする。

### 4.3 Human-readable text

新規のPlain Text LogやUser-facing TextをFileへ出力する場合もUTF-8を基本とする。

Legacy Toolで読む必要があるFileだけCompatibility上のEncodingを個別指定する。

---

## 5. BOM Policy

Read時は少なくとも次を認識する。

- UTF-8 BOM
- UTF-16 LE BOM
- UTF-16 BE BOM

BOMが存在する場合は、そのEncoding指定を優先する。

BOMなしTextについてはContext-awareな判定を行う。

一般的な優先順位候補:

```text
Known format declaration
        ↓
BOM
        ↓
Valid UTF-8
        ↓
Known legacy contextのCP932
        ↓
Encoding unknown / error
```

Encoding Detectionを無制限な推測Engineにはしない。

「何となく読めそうなEncoding」を片っ端から試して最初に成功したものを採用する方式は避ける。

---

## 6. CP932 / Shift_JIS Compatibility

v1系Windows Applicationとの互換性では、実際にはWindows-31J / CP932系の文字を含む可能性がある。

そのためLegacy Compatibility Codecとしては、単純なStrict Shift_JISだけではなくCP932を明示的に扱う。

Document / UI上で「Shift_JIS」と表現する場合でも、Legacy Windows DataのDecode / Encode実装はCP932との違いを意識する。

### 6.1 CP932を許可する主なContext

- v1.x Configuration
- LFCaldix関連Data
- 旧Toolが生成したText
- Legacy DLLのANSI API
- `cldx`内のLegacy Documentation
- Legacy Japanese Archive Metadata

### 6.2 ACPへの暗黙依存を避ける

```text
GetACP() = 932だからCP932として扱う
```

というSystem Locale依存だけでData Formatを決めない。

Japanese Windows以外でも同じLegacy Dataを扱えるよう、EncodingはContext / Format / Configurationから決定する。

---

## 7. Newline Policy

LhaForgeが管理するText Readerは、必要なFormatにおいて少なくとも次を認識する。

- CRLF
- LF
- CR

Read時に改行差だけでLegacy DataをRejectしない。

### 7.1 Write policy

Human-readable Windows Textを新規生成する場合はCRLFをDefault候補とする。

Machine-readable / Deterministic SerializationではFormat側でCanonical Newlineを定義し、PlatformによりByte列が変わらないようにする。

既存Legacy Configを編集する場合は、可能な限り元の改行形式をPreserveする。

Archiveから展開したUser Fileの改行は変換しない。

---

## 8. Configuration Encoding

ConfigurationはOwnershipとConsumerにより扱いを分ける。

### 8.1 LhaForge.ini

Legacy `LhaForge.ini`をMigrationする場合:

1. 元FileをByte単位でBackupする。
2. Encoding / newlineを判定する。
3. Known SettingをUnicode Setting ModelへDecodeする。
4. Unknown Settingを可能な限りPreserveする。
5. 変換不能値をDefaultへ黙って置換しない。

新Configuration Formatへ移行するか、既存INIを継続するかはConfiguration設計で最終決定する。

### 8.2 LFCaldix.ini

`LFCaldix.ini`はLhaForgeだけが所有するFileではなく、LFCaldixとのShared Compatibility Configurationとして扱う。

Legacy LFCaldixがConsumerとして残る間は、LhaForge側だけの都合でUTF-8へ無条件変換しない。

```text
Existing LFCaldix.ini
        ↓
Detect legacy encoding
        ↓
Read as Unicode internally
        ↓
Write back only in a representation
that all active consumers can read
```

Consumer Compatibilityが確認できるまではCP932 / Legacy Encoding維持を安全側の候補とする。

### 8.3 New v1.7 settings

v1.7.xで新設するSetting Storeは、Legacy Consumerとの共有が不要ならUTF-8 / Unicode Nativeを利用する。

例:

- Exclusion Rules
- Backend Policy
- Logging Policy
- Security Policy
- Archive-name extraction policy

Legacy Shared Fileへ新機能を無理に詰め込まない。

---

## 9. Archive Entry Name Model

Archive Entry NameはUser File Contentsとは別のMetadataであり、安全なDecodeとPath Validationが必要になる。

概念Model:

```text
ArchiveEntryName
├─ Decoded Unicode Name
├─ Raw Name Bytes           (Backend / Formatが取得可能な場合)
├─ Encoding Source
├─ Encoding Confidence
└─ Validation State
```

Built-in Backend / AdapterがRaw Nameを取得できる場合は、Decode結果だけでなく元情報を保持できる構造を検討する。

これにより、Encoding判定の再試行や診断が必要な場合に、既にLossy変換されたStringだけへ依存しなくて済む。

---

## 10. Archive File Name Decoding Priority

Archive FormatごとにEncoding Specificationが異なるため、一律CP932とはしない。

優先順位の概念:

```text
Format-defined Unicode metadata
        ↓
Backend Unicode API result
        ↓
Format-specific encoding declaration / extra field
        ↓
Explicit user / compatibility policy
        ↓
Known legacy Japanese fallback
        ↓
Undecodable
```

ZIP、TAR等の詳細PolicyはBackend / Format Adapter単位で定義する。

### 10.1 Legacy Japanese ZIP

Legacy ZIPにはUTF-8 Flagが存在せず、File Name byte列がCP932等で格納されているArchiveが存在する。

v1系Compatibility上、このCaseを考慮する。

ただし、

```text
UTF-8でDecode失敗したから常にCP932
```

のようなFormat非依存Fallbackにはしない。

Format Policy、User Setting、Archive由来情報を組み合わせる。

### 10.2 Ambiguous encoding

複数Encodingで有効にDecodeでき、正しいNameを一意に決められない場合は、必要に応じてCompatibility PolicyまたはUser選択を利用する。

変換結果を確定できないのに、別のFile Nameとして黙って展開しない。

---

## 11. Security Validation after Decode

Encoding Decodeに成功しただけでは安全なPathではない。

Unicode Nameへ変換した後、共通Security Layerで次を検証する。

- Path Traversal
- Absolute Path
- Drive / UNC / Device Path
- NUL
- NTFS ADS
- Reserved Device Name
- Trailing Dot / Space
- Alternate Separator
- Control Character
- Bidirectional Control Character
- Reparse Point関連Policy
- Collision
- Path Length / Resource Limit

Encoding LayerとPath Security Layerの責務を混同しない。

```text
Raw metadata
    ↓ Decode
Unicode path
    ↓ Normalize for comparison only
Security validation
    ↓
Safe operation path
```

---

## 12. Unicode Normalization

Original Nameを保存・表示する目的で、Unicode NormalizationによりFile Nameを黙って書き換えない。

一方Security / Collision判定では、必要に応じて比較用Canonical Keyを別途生成できる設計とする。

```text
Original Unicode Name
        │
        ├─ Display / actual name
        │
        └─ Security comparison key
```

Normalizationによって2つの異なるEntryが同一TargetへCollisionする場合は、上書きせずCollisionとして扱う。

Compatibility Normalizationによる見た目の似た文字の置換をFile Name変更目的で使用しない。

---

## 13. Invalid Unicode / Control Characters

Invalid UTF Sequence、Unpaired Surrogate、Embedded NUL等を正規のFile Nameとして通さない。

List UI等で診断表示が必要な場合は、

- Escaped representation
- Entry index
- Encoding error reason

等を利用できるが、そのDisplay StringをそのままFilesystem Pathとして使用しない。

Bidirectional Control Character等は必ずしも全て禁止とは限らないが、Security Policy上のWarning / Block対象を定義できるようにする。

---

## 14. Legacy DLL Boundary

Legacy DLLがANSI APIのみを提供する場合、Adapter / LegacyHostでEncoding変換を行う。

```text
LhaForge Unicode Path
        ↓
Can represent in required legacy encoding?
        ├─ Yes → Encode → Legacy DLL
        └─ No  → Capability failure
```

### 14.1 No best-fit fallback

例えばUnicode File NameがCP932で正確に表現できない場合、似た文字や`?`へ置換してDLLへ渡さない。

Backend Selectionへ次の情報を返せるようにする。

```text
Backend supports operation
but cannot represent selected path / entry name
```

Operation開始前であれば、Unicode対応x64 BackendまたはBuilt-in BackendへFallbackできる。

### 14.2 DLL output

ANSI DLLから返されたTextもAdapter BoundaryでUnicodeへDecodeする。

DLLごとにExpected Encodingが異なる場合、Backend Descriptor / Adapter Policyで明示する。

System ACPの値だけで自動決定しない。

---

## 15. LegacyHost IPC Encoding

LhaForge x64とLegacyHost x86間のIPCでは、String EncodingをProtocol Specificationで固定する。

初期候補はWindows Native Modelと変換Costを考慮してUTF-16LEのLength-prefixed Stringとする。

```text
Protocol Header
String byte length
UTF-16LE payload
```

要件:

- NUL終端だけへ依存しない
- Lengthを必ずBounds Checkする
- Odd byte lengthをRejectする
- Invalid surrogate sequenceをRejectする
- Message全体のMaximum Sizeを設定する
- Protocol VersionでEncoding Contractを固定する

IPC EncodingをSystem Localeに依存させない。

最終Wire FormatはLegacyHost IPC PoCで確定する。

---

## 16. Command Line / Shell

v1.7.x Main ApplicationはWide Character Command Lineを利用する。

Shellから渡されるPathをANSI Command Lineへ変換してから再Decodeする経路を作らない。

Legacy Helperへ引数を渡す場合も、可能ならWide API / Structured IPCを利用する。

Command LineへPassword等のSecretを含めない方針はSecurity設計に従う。

---

## 17. Logging Encoding

新しいFile LogはUTF-8 BOMなしをDefaultとする。

External DLL / LegacyHostから受け取ったLegacy StringはUnicodeへ変換してからLogging Coreへ渡す。

Raw Legacy byte列をそのままLogへ混在させない。

Log RecordのMessage内に含まれる改行、Control Character等はLog Injection防止Policyに従ってEscape / Sanitizeする。

既存CP932 LogをImport / Displayする機能を将来実装する場合は、Read Compatibilityとして扱い、新規LogのDefault Encodingにはしない。

---

## 18. Installer / Migration Metadata

Installer Lifecycleが新規生成するPackage Manifest、Install State、Recovery Metadata、Journal等はLocale非依存のUnicode Formatを利用する。

Text Formatを採用する場合のDefaultはUTF-8 BOMなしとする。

Machine-readable Dataでは、

- Encoding
- Newline
- Serialization order（必要な場合）
- Version
- Schema

を明確化し、Hash / Signature VerificationがLocaleやEditor差で壊れない設計とする。

Migration LogとTransaction Journalは別物であり、Encodingも各Format Contractに従う。

---

## 19. Migration of Legacy Text

Legacy Text Migrationでは、最初に元Byte列をPreserveする。

```text
Original bytes
      ↓ backup
Detect / decode
      ↓
Unicode logical model
      ↓
Schema-aware migration
      ↓
Target serialization
```

Decode前のDataを失わない。

変換不能部分がある場合は、元Fileを破壊して不完全な新Fileへ置換しない。

Migration JournalへEncoding判定結果を記録できるようにするが、Secret Valueそのものは記録しない。

---

## 20. cldx Policy

`cldx`はLegacy Documentation / SDK / Source / License等を含むLFCaldix-managed Asset領域であり、Encoding Modernizationの対象として一括変換しない。

特に、Legacy Japanese FilenameやCP932 Textが存在し得る。

```text
cldx\読んでね.txt
```

はRegression Test Caseとして利用する。

確認項目:

- File Nameが文字化けしない
- CP932内容を必要に応じて正しく表示できる
- MigrationでByte内容を変更しない
- CleanupでEncodingを理由に削除しない

Third-party DocumentationのEncodingをLhaForge都合で書き換えない。

---

## 21. Repository Text / File Name Policy

Repository自体のEncoding事故を防ぐため、v1.7.xで新規追加・変更するSource / Markdown / Text Fileは原則UTF-8を使用する。

Repositoryで新規に管理するSource / Design Document File Nameは原則ASCIIを使用し、日本語TitleはMarkdown本文に保持する。Unicode File Nameが必要なCompatibility Test Dataは例外として明示管理し、文字化けしたbyte sequenceをCommitしない。

### 21.1 Repository path rule

- 新規のSource / Design Document File Nameは原則ASCIIを使用する
- Unicode File Nameが必要なFixture / Compatibility Test Dataは例外として明示管理する
- ZIP等で配布するSource TreeはWindows標準展開を含む複数実装でPathのRound-tripを確認する
- 同一Documentを異なるEncoding由来のFile Nameで重複させない
- Rename時は旧文字化けFileを削除したことを確認する
- GitHub上でRelative Linkが解決することを確認する

### 21.2 Markdown links containing spaces

File NameにSpaceが存在する場合、Markdown Relative LinkではSpaceをURL Encodeする。

例:

```markdown
[ADR-0004](../../adr/0004-built-in-backend-fallback.md)
```

将来的なCIで、Tracked PathのUTF-8妥当性とMarkdown Relative Linkの存在確認を自動化することを検討する。

### 21.3 Windows PowerShell 5.1 Script Exception

RepositoryのText Fileは原則UTF-8 BOMなしとするが、`powershell.exe`で実行するWindows PowerShell 5.1向け`.ps1`は例外として扱う。

Windows PowerShell 5.1はUTF-8 BOMなしのScriptをSystem ANSI Code Pageとして解釈するため、日本語等のNon-ASCII文字を含むUTF-8 BOMなしScriptはParser Errorや文字化けを起こし得る。

互換性を優先し、Windows PowerShell 5.1でも実行するRepository管理Scriptは次のいずれかとする。

1. Script本文をASCIIのみで記述する。
2. Non-ASCII文字が必要な場合はUTF-8 BOM付きで保存し、そのEncoding要件を明示する。
3. PowerShell 7以上専用Scriptにする場合は`pwsh`専用であることを明示し、Windows PowerShell 5.1から実行させない。

PoC 1の`tools/verify-vs-environment.ps1`はWindows PowerShell 5.1互換を必要とするため、ASCII-onlyで管理する。

### 21.4 Existing source.txt

`source.txt`はv1.7.x開発準備時にUTF-8 BOMなしへ変換済みである。

これは公式v1.6.7 Source ArchiveとのBaseline Verification後に行ったRepository Modernizationであり、`ver_1_6_7` Tag自体は変更しない。

---

## 22. Encoding Detection Safety

Encoding DetectionはUntrusted Input Parserとして扱う。

必要な防御:

- 最大File Size / Scan Size
- Integer Overflow防止
- Invalid Sequence処理
- Excessive Backtrackingを持つHeuristicを避ける
- BOMだけで危険なPathをTrustしない
- NUL / Control Character Validation
- Decode後のPath Security Validation

巨大File全体をMemoryへ読み込みEncoding判定する方式を避け、必要に応じて先頭BufferやStreaming Decoderを利用する。

---

## 23. Performance Policy

Encoding変換がArchive処理のHot Pathを不必要に悪化させないようにする。

原則:

- 同じPathをBackendごとに何度もEncode / Decodeしない
- Operation Plan内で必要な変換結果をCache可能にする
- Entry MetadataはBoundedな単位で処理する
- Log用String生成をTrace無効時まで常に実行しない
- LegacyHost IPCでStringを1文字ずつ送らない
- 大量EntryではBatch / Streamingを利用する

Performance最適化のためにLossy Conversionへ戻さない。

---

## 24. Error Model

Encoding関連Errorは「Archiveが壊れている」等の一般Errorへ潰さず、原因を区別できるようにする。

概念Error:

```text
EncodingUnknown
EncodingInvalidSequence
EncodingUnsupported
EncodingLossyConversionRequired
LegacyBackendCannotRepresentName
InvalidUnicodePath
UnicodeCollision
IPCStringInvalid
```

UIでは必要に応じて分かりやすい日本語へ変換する。

Diagnostic LogにはEncoding種類、Backend ID、Entry Index等を記録できるが、機密Path全文をDefaultで記録するとは限らない。

---

## 25. User-facing Compatibility Options

必要な場合、Advanced OptionとしてArchive File Name Encoding Policyを提供できる設計とする。

候補:

```text
Auto / Format default
UTF-8
CP932
Backend default
```

ただし設定数を増やし過ぎない。

通常UserはAutoで安全に利用でき、Legacy ArchiveでのみOverrideする方向とする。

Override設定はArchive ContentsのText Encoding変換機能ではなく、Archive Entry MetadataのDecode Policyであることを明確にする。

---

## 26. Test Matrix

最低限次をRegression Testへ含める。

### Unicode

- ASCII File Name
- 日本語File Name
- Emojiを含むFile Name
- Supplementary Plane Character
- Combining Character
- Long Unicode Path

### Legacy encoding

- CP932 Text
- CP932 File Name Metadata
- UTF-8 BOM
- UTF-8 BOMなし
- UTF-16 LE BOM
- UTF-16 BE BOM
- CRLF
- LF
- CR

### Conversion failure

- CP932へ表現不能なUnicode Path
- Invalid UTF-8
- Invalid UTF-16 surrogate
- Embedded NUL
- Ambiguous Legacy ZIP Name

### Compatibility

- v1.6.7 `LhaForge.ini`
- `LFCaldix.ini`
- `cldx\読んでね.txt`
- External ANSI DLL
- Unicode対応External DLL
- LegacyHost round-trip

### Security

- Unicodeを利用したTraversal表現
- Alternate Slash / Separator
- Bidi Control Character
- Reserved Device Name
- Decode後Collision
- Log Injection文字列

---

## 27. Acceptance Criteria

Encoding Modernizationの初期完了条件として、少なくとも次を満たす。

1. Main ApplicationがWide Win32 APIを基本利用する。
2. Unicode PathをApplication Core内でLossy変換しない。
3. Legacy DLLへのCP932変換不能を検出できる。
4. 新規First-party TextのDefault Encodingが定義されている。
5. Legacy Configurationを元Byte列付きでMigration可能である。
6. Archive Entry NameのDecodeとPath Securityを分離できている。
7. User File Contentsを自動変換しない。
8. LegacyHost IPCのEncoding Contractが明示されている。
9. CP932 / UTF-8双方のRegression Testが存在する。
10. Repository上のTracked File Nameが文字化けした重複状態にならない。

---

## 28. Open Items

- v1.7.x Configuration Storeの最終Format
- Existing INIへ書き戻す際のEncoding / newline Preserve実装
- ZIP Legacy FilenameのFormat-specific Auto Detection詳細
- Built-in Backend Libraryが提供するRaw Name Metadataの範囲
- Legacy DLLごとのExpected ANSI Encoding
- LegacyHost IPC Wire Formatの最終確定
- Repository向けEncoding / Link Check CIの実装方法
- `.gitattributes`によるSource Text Policyの要否

---

## 29. Architecture Principle

Encoding Compatibilityは、

```text
すべてをUTF-8へ変換すること
```

ではない。

v1.7.xでは、

```text
Unicodeを内部標準にする
        +
Legacy EncodingをBoundaryで正しく扱う
        +
Original Dataを不用意に変換しない
        +
Lossy Conversionを黙認しない
        +
Security ValidationをDecode後にも行う
```

ことをEncoding Modernizationの基本原則とする。

### Windows PowerShell 5.1 and native UTF-8 JSON

`powershell.exe` (Windows PowerShell 5.1) からnative processのUTF-8 JSONを直接Pipelineで`ConvertFrom-Json`へ渡す実装は避ける。localized stringを含む出力がactive code pageで誤Decodeされ、JSON自体が破損する場合がある。

Environment verifierでは`vswhere -format json -utf8 | ConvertFrom-Json`を使用せず、必要な`-property`を個別に取得する。JSONが必要な場合はbyte-levelでEncodingを明示してDecodeするか、PowerShell 7専用処理として分離する。

