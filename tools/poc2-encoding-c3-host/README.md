# PoC 2-C3 Host-side Fixture Tooling

このDirectoryはPoC 2-C3 `ZIP Entry Name Metadata / Cross-platform oriented Fixture`のうち、VM実行前にHost PCだけで完了できる作業を分離したToolingです。

現段階ではLhaForge Original / Modernの実行は行いません。まずRaw ZIP FixtureそのものをDeterministicに生成し、別Parserで構造とSHA-256を検証してからFormal VM Kitへ進みます。

## Scope

Host側で次を固定します。

- ZIP Local File Header / Central DirectoryのRaw Filename Bytes
- General Purpose Bit Flag bit 11 (EFS / UTF-8)
- Info-ZIP Unicode Path Extra Field `0x7075`
- `0x7075` Version / NameCRC32 / UnicodeName
- CP932 Legacy Name
- UTF-8 / Emoji / NFC / NFD
- ambiguous byte sequence
- malformed UTF-8 / malformed Unicode Path metadata
- `.DS_Store` / `__MACOSX/` / `._*`相当Metadata
- Fixture Archive SHA-256
- Entry Payload SHA-256

生成Archiveは`.baseline\poc2-encoding\c3-fixtures\`へ出力し、Git管理しません。

## Why raw ZIP generation is required

通常のZIP LibraryへFilename文字列を渡してFixtureを作ると、Library側が次を自動決定する可能性があります。

- EFS bit 11
- Filename Encoding
- Unicode Extra Field
- Local / Central Header metadata
- Timestamp / Attribute

C3ではそれら自体が試験対象なので、Fixture BuilderがRaw Headerを直接構築します。

## LhaForge-side source boundary

現在のLhaForge `CArchiver7ZIP`では、

1. `7-ZIP32.DLL` 9.22.0.2を要求する。
2. `SevenZipSetUnicodeMode(TRUE)`を必須としている。
3. Archiveを`SevenZipOpenArchive(..., C2UTF8(ArcFileName), ...)`で開く。
4. `SevenZipGetFileName()`等から受け取ったFilename byte列をLhaForge側で`UTILCP_UTF8`としてUnicodeへ変換する。

したがってC3では、

```text
ZIP raw metadata
    ↓
7-ZIP32.DLL 9.22.0.2 interpretation
    ↓
7-ZIP32 API byte representation
    ↓
LhaForge UTF-8 boundary
    ↓
List / Extract filesystem name
```

を観測します。

Historical Backend内部でどのMetadataが優先されたかをLhaForge側だけから推測せず、Raw Fixtureと実動結果を対にしてEvidence化します。

## ZIP specification anchors

Primary reference:

- PKWARE APPNOTE.TXT 6.3.10
  - https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

C3で特に使用するRule:

- General Purpose Bit Flag bit 11がsetの場合、Filename / CommentはUTF-8でなければならない。
- Info-ZIP Unicode Path Extra FieldはHeader ID `0x7075`。
- `0x7075` Dataは`Version(1 byte) + NameCRC32(4 bytes) + UnicodeName(UTF-8)`。
- NameCRC32は対応するHeaderのFile Name FieldのCRC32。
- NameCRC32が一致しない場合、Unicode Path Extra Fieldはignoreすべきと定義される。
- 現行定義Versionは1で、未知Versionは使用しないことが推奨される。
- bit 11方式とUnicode Path Extra Field方式の両方をReaderが想定すべきとされる。
- bit 11を使用する場合、Unicode Path Extra Fieldは通常不要であり作成すべきではない。

## Historical 7-ZIP32 context

Historical baseline:

```text
7-ZIP32.DLL
Version: 9.22.0.2
SHA-256: A82D2B10960F9EBAF5B9D56E2F495C72C22F5DE542740D585AB14CB0B291999C
```

Official Common Archivers Library page:

- https://www.madobe.net/archiver/lib/7-zip32.html

`7-zip32_ungarbled`の履歴はHistorical 9.22のExpected Behaviorを決める一次資料にはしませんが、後年にFilename処理が継続して修正されたことを示す参考資料として利用します。

特に履歴上、

- 15.05系で日本語List文字化け修正
- 15.06系でInfo-ZIP Unicode Path Extra FieldとCode Pageの優先順位調整
- 15.07系で未指定時の文字コード変換方針変更
- 15.09系で`SevenZipSetCP()` / `SevenZipGetCP()`追加、`SevenZipSetUnicodeMode()`によるCode Page指定廃止
- 15.14系で本家7-Zip側が対応したため独自`0x7075`処理を削除

という変更があります。

そのため、9.22について「現行仕様ならこうなるはず」と決め打ちせず、C3ではOriginal / ModernのHistorical Behaviorを観測します。

Reference:

- https://github.com/ytakanashi/7-zip32_ungarbled

## Windows PowerShell 5.1 zero-length byte arrays

ZIP Directory EntryのStored Payloadや、Extra Fieldを持たないEntryではzero-length byte arrayが正常に現れる。Windows PowerShell 5.1はMandatoryなArray Parameterへ空Collectionを渡す場合、Parameter側で明示的に許可しないとBinding Errorにする。

Generator / Validatorではzero-lengthを意味的に許容するParameterへ`AllowEmptyCollection`を付与し、Fixture処理へ入る前にempty byte-array smoke testを実行する。

## Commands

Repository RootでWindows PowerShell 5.1を使用します。

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\poc2-encoding-c3-host\generate-fixtures.ps1
```

続けてIndependent Validatorを実行します。

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\poc2-encoding-c3-host\validate-fixtures.ps1
```

成功時の最後は概ね次になります。

```text
[POC2-C3] Validation PASS. Cases=15
```

`generate-fixtures.ps1`は`fixture-manifest.json`も生成します。


## Host validation freeze

Status: **PASS (2026-08-30)**

Validated repository HEAD before adding this tooling:

```text
745305d4867fe3ae0a134e3198c5b6ae0d619e21
Document upstream-first backend policy
```

Host execution:

```text
Windows 10.0.26200.9168
Windows PowerShell 5.1 Desktop (script-enforced)
Generator empty byte-array smoke test: PASS
Validator empty byte-array smoke test: PASS
Generated cases: 15
Independent validation: 15 / 15 PASS
```

The first host-tooling revision exposed a Windows PowerShell 5.1 parameter-binding issue for a legitimate zero-length `byte[]` used by the `__MACOSX/` directory entry. This was a tooling defect, not an LhaForge behavior result. The current scripts explicitly allow zero-length byte collections where semantically valid and run smoke tests before fixture processing.

The fixture SHA-256 values below are frozen by `validate-fixtures.ps1` and reproduced by the host run.

| Fixture | SHA-256 |
| --- | --- |
| `ascii` | `ce18a398ab39e50f4215c76132602888b59612be150c5c1f46cd2316ef161e2a` |
| `utf8-japanese` | `3157c1131c0bb9fd09802e3716a6892482101f133b089717c1731e4a48bfb12b` |
| `utf8-emoji` | `2917aeef94e2f0b130fc9978fc55968643243c1857c338aec700d641905b5298` |
| `utf8-nfc` | `0c5523eda6b603eaa0c19d5a55e78a6255e045a4e96d4915639d8c535c95b51d` |
| `utf8-nfd` | `7604c32e7c24626a65df4fcfcc48ceddd8c68cca08009bcc2f632f4e9fbd77cd` |
| `cp932-japanese` | `a3937ae3d1ce93464f754e788187f5c7727e47cb8e542695e9735f8fa4bfabe4` |
| `cp932-ambiguous` | `b70295e558d4e32c8c6afeb24a89c1ade8753b85b69b3b605df44c7bcc113a9b` |
| `cp932-upath-valid` | `ce769489ef71130a0ee1a9893b51e768825f235f6b396684f9b87bce2bd9667c` |
| `cp932-upath-bad-crc` | `4590a945bc06557628ecea0a1b28d18ea69645a263ff6de22ca7d57f6232f456` |
| `cp932-upath-conflict` | `f02a51af7bc966d503355479cabd1a5ed32956fd4c4b72039ff7f40b7f7357a9` |
| `utf8-upath-conflict` | `ef9d577380b5eda37a76a1cf4712311a68323f13971b89b111676ed2066fc93b` |
| `invalid-utf8-flag` | `f5a66a68d901a9f0c98f16aecd3df696cebd1f2009aaa04b02fff5394f69dcb8` |
| `upath-invalid-utf8` | `8717cbc1e393b46638cd5d6a8728e654b7d0c4d912004ea12229641aa4e21bcb` |
| `upath-unknown-version` | `4f34cccf47f14a653dece50e0b4591f73e46d4b8b417a604048631a5f78aa211` |
| `macos-metadata` | `0668be22ca3671dc21bba6e69be000b024727eff156324a109ae18fe59ec0021` |

## Stop conditions

次の場合はVMへ進まず、その時点で停止します。

- GeneratorのArchive SHA-256がValidatorのReference Hashと一致しない。
- Local HeaderとCentral DirectoryのFilename / Flags / Extra Fieldが一致しない。
- Stored payload CRC / SHA-256が一致しない。
- Expected 15 Fixture以外のZIPが出力される。
- PowerShell RuntimeがWindows PowerShell 5.1 Desktopではない。
- Fixture outputに構造Errorがある。

## After host validation

Host ValidationがPASSした後に次を行います。

1. Fixture Matrixを`regression-encoding.md`へFreeze。
2. C3専用Result / Evidence Documentを追加。
3. Formal VM KitへFixtureとManifestをStage。
4. Original v1.6.7 + 7-ZIP32.DLL 9.22.0.2を実行。
5. Modern x86を同一Fixtureで実行。
6. List / Test / Extract / filesystem name / code pointsを比較。
7. 将来PoC 4のOfficial `7z.dll` Backendへ同じFixtureを再利用。

Host Validationが通るまではVM実行用Scriptを追加しません。
