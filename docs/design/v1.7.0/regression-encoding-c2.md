# PoC 2-C2 Response File Encoding / Newline Regression Result

- Status: **Complete / Normal MATCH; Abnormal SECURITY_CHANGE_REQUIRED**
- Normal executed: 2026-08-13
- Abnormal executed: 2026-08-23
- Scope: Original LhaForge v1.6.7 vs Modern x86 Release
- Normal tested repository HEAD: `ef915cad9913582f42bdd737d33104c4e77dd1b8`
- Abnormal tested repository HEAD: `d1e28e1c75399ea8ce6f187d0329e50a9e519c0d`
- Development branch: `develop-v1.7.0`
- Fixed backend: `7-ZIP32.DLL` 9.22.0.2 / x86
- Fixed backend SHA-256: `a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c`

Related documents:

- [PoC 2-C Encoding / Path Regression Plan](regression-encoding.md)
- [PoC 2-C1 Direct Unicode Path Regression Result](regression-encoding-c1.md)
- [Regression Baseline](regression-baseline.md)
- [PoC Plan](poc-plan.md)

---

## 1. Purpose

PoC 2-C2では、x64化やFilename Decode LayerのProduction実装へ進む前に、Legacy command line parserが持つResponse FileのEncoding / BOM / Newline / parser stateをOriginal v1.6.7とModern x86で比較した。

このResultは**正常系BaselineとAbnormal Baselineの両方**を記録する。正常系はEncoding / BOM / Newline / parser stateを固定し、Invalid `/cp`、Invalid UTF-8、lone surrogate、odd-length UTF-16は正常系から分離したAbnormal Caseとして後日同一方針で実行した。

C2ではResponse File自体のPathをASCII-onlyへ固定し、C1 Direct Unicode Pathの変数を再混入させない。Response File内で選択されたTarget PathだけにUnicode categoryを含めた。

---

## 2. Fixed environment and evidence identity

最終Runで使用した主要Identity:

```text
Repository HEAD
ef915cad9913582f42bdd737d33104c4e77dd1b8

VM Kit ZIP SHA-256
9a10c1e3671680a3402fd3fd7823a714c40ceeb9299603a9278185ee0c3914fa

Frozen normal evidence ZIP SHA-256
679d13c404d174c31c2013f3e62b2e937abbb2f1ecc88d2b44c516a3f7a4ff69

Original LhaForge.exe
Size:    1,001,984 bytes
PE:      0x014c (x86)
SHA-256:
7326c767fe308f03bfb61ac15b9ba97be43385877667e63751e5962d8b2ac846

Modern LhaForge.exe
Size:    1,049,088 bytes
PE:      0x014c (x86)
SHA-256:
7d3bc5db76618709e7518badb649fcf6b1606567397034265ac330e10837dff7

7-ZIP32.DLL
Version: 9.22.0.2
Size:    640,512 bytes
PE:      0x014c (x86)
SHA-256:
a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c
```

VM-side regression tooling runtime recorded in Evidence:

```text
Windows PowerShell: 5.1.26100.8875
PSEdition:          Desktop
CLR:                4.0.30319.42000
ANSI code page:     932
Culture:            ja-JP
UI Culture:         ja-JP
OS:                 Microsoft Windows NT 10.0.26200.0
```

C2 normal baselineはWindows PowerShell 5.1 / ACP932をEnvironment Gateとし、設定を自動変更せず、自然なLegacy ANSI conversion behaviorを観測した。

Evidence capture時刻:

```text
State before      2026-08-13T11:22:17.6265607Z
Original capture  2026-08-13T11:45:01.8482666Z
Modern capture    2026-08-13T11:54:48.3907808Z
Final compare     2026-08-13T11:55:40.9652755Z
```

---

## 3. Legacy parser behavior fixed before execution

Source archaeologyから、正常系Baselineで次を固定した。

1. Response File Code Pageの初期値はSJIS。
2. `/cp:utf8` / `/cp:utf-8`はUTF-8へ切り替える。
3. `/cp:utf16` / `/cp:utf-16` / `/cp:unicode`はUTF-16へ切り替える。
4. `/cp:sjis`系AliasはSJISへ切り替え、bare `/cp`もSJISへ戻す。
5. ParserはCommand Lineを左から右へ処理するため、`/cp`はその後に読むResponse Fileへ適用される。
6. `/@file`は正常読込後もResponse Fileを保持する。
7. `/$file`は正常読込後にResponse Fileを削除する。
8. Response File Readerは変換後の`CR`、`LF`、`NUL`を独立した区切りとして扱い、空行を無視する。
9. UTF-8はBOMあり / なしを扱う。
10. UTF-16はLE BOM / BE BOMを識別し、BOMなしはNative UTF-16LEとして扱うLegacy behaviorを持つ。

これらは新仕様ではなく、Original / Modern間で固定するLegacy behaviorの観測対象である。

---

## 4. Fixture and comparison design

CP932 CaseはASCII + CP932 representable Japaneseを使用した。

UTF系Caseは次の7 categoryを使用した。

```text
ASCII
Japanese
Emoji
Supplementary Plane
Combining Character
NFC
NFD
```

Response Fileから選択されたInput SetはZIPへ圧縮し、ZIP内部のEntry Name + Payload SHA-256からlogical fingerprintを作成してExpected Input Setと比較した。

Primary Evidence:

- Response File raw SHA-256 / size
- Encoding / BOM / Newline / directive metadata
- Command line argument order
- Expected input set
- Generated ZIP Entry Name
- Payload SHA-256
- logical archive fingerprint
- `/@` / `/$` post-state
- Process result / crash classification
- External AppData / ProgramData state
- Temp ZIP state

Generated ZIP全体のbyte SHA-256一致はSecondary Observationとし、Primary pass criterionには昇格させない。

---

## 5. Normal matrix result

Original / Modernとも同じ11 Caseを1件ずつ実行した。

```text
Case                       Original  Modern  Response post-state
sjis-crlf                  PASS      PASS    /@ preserved
utf8-nobom-crlf            PASS      PASS    /@ preserved
utf8-bom-crlf              PASS      PASS    /@ preserved
utf16le-bom-crlf           PASS      PASS    /@ preserved
utf16be-bom-crlf           PASS      PASS    /@ preserved
utf16le-nobom-crlf         PASS      PASS    /@ preserved
utf8-nobom-lf              PASS      PASS    /@ preserved
utf8-nobom-cr              PASS      PASS    /@ preserved
sequence-sjis-then-utf8    PASS      PASS    /@ a/b preserved
sequence-utf8-reset-sjis   PASS      PASS    /@ a/b preserved
dollar-delete-utf8         PASS      PASS    /$ deleted
```

Process evidence:

```text
Original run records: 11
Modern run records:   11
Exit code 0:          11 / 11 for each target
Crash classification: none
```

Expected logical archive fingerprints:

```text
sjis-crlf
bc4ae1f13b5f180a0e026919111c851ced880366fdab28a3385ae7c73c7e5a5d

UTF / sequence / dollar cases
f80ac96dd67b314f9c7b737d92fbec4ae45f5bb7c07cdaae18ba1bebc52562ed
```

Original / Modern双方で各Caseのactual fingerprintがExpectedと一致した。

---

## 6. Encoding / newline / parser-state observations

正常系Runから次を確認した。

### 6.1 Encoding / BOM

```text
CP932 / CRLF               MATCH
UTF-8 / no BOM / CRLF      MATCH
UTF-8 / BOM / CRLF         MATCH
UTF-16LE / BOM / CRLF      MATCH
UTF-16BE / BOM / CRLF      MATCH
UTF-16LE / no BOM / CRLF   MATCH
```

### 6.2 Newline

```text
CRLF   MATCH
LF     MATCH
CR     MATCH
```

### 6.3 Parser state

`sequence-sjis-then-utf8`では、既定SJISで最初のCP932 Response Fileを読み、その後`/cp:utf8`へ切り替えてUTF-8 Response Fileを読んだ。Original / Modernとも同一Input Setとなった。

`sequence-utf8-reset-sjis`では、`/cp:utf8`でUTF-8 Response Fileを読んだ後、bare `/cp`でSJISへ戻してCP932 Response Fileを読んだ。Original / Modernとも同一Input Setとなった。

### 6.4 Response File lifetime

`/@` CaseはWorking Copyがbyte-identicalのまま残り、`/$` Caseは正常読込後に削除された。Original / Modernのpost-state差異はなかった。

---

## 7. Final comparison

最終Comparison:

```text
[POC2-RSP] Classification: MATCH
[POC2-RSP] OBS: 11 of 11 generated ZIP byte SHA-256 pairs are identical.
```

`comparison.json`:

```text
classification:               MATCH
issueCount:                   0
caseCount:                    11
identicalZipByteHashCount:    11
ansiCodePage:                 932
```

Final comparatorは、Original / Modernのsuccess、argument plan、Expected archive fingerprint、Response File raw identity / metadata / post-state、External AppData / ProgramData stateを比較し、Issueを検出しなかった。

さらにFrozen Evidenceを別途再解析し、Case set、process result、argument plan、archive fingerprint、Response raw identity、directive post-state、Original / Modern ZIP byte SHA-256、external / temp stateを独立に照合した結果も**不整合0件**だった。

11 / 11のGenerated ZIP byte SHA-256一致は強いSecondary Evidenceだが、将来のZIP metadata差をRegressionと誤判定しないためPrimary criterionにはしない。

---

## 8. Tooling correction discovered before the formal run

C2 Tooling初版は次のCommitで追加した。

```text
09ff75cb98b18686444cbdcf68f910448e8485d6
Add PoC 2-C2 response file regression tooling
```

最初のVM initializationでは、Windows PowerShell 5.1で`Get-Poc2C2EncodedBytes`のBOMなしCaseを生成する際、空の`byte[]`がPipelineでunrollされて`$null`となり、StrictMode下の`$preamble.Length`参照でHarnessが停止した。

```text
Get-Poc2C2EncodedBytes :
このオブジェクトにプロパティ 'Length' が見つかりません...
```

このFailureはLhaForge起動前かつ`state-before.json`生成前に発生しており、Product regressionには分類しない。

修正Commit:

```text
ef915cad9913582f42bdd737d33104c4e77dd1b8
Fix PoC 2-C2 response byte generation
```

修正ではbyte arrayを明示型で保持し、`Write-Output -NoEnumerate`で単一`byte[]`として返すようにした。さらにHost prepare / VM initializeの双方へEncoding byte generator smoke testを追加し、次のExact Byteを検証した。

```text
CP932 ASCII        41
CP932 Japanese     93FA967B8CEA
UTF-8 no BOM       41
UTF-8 BOM          EFBBBF41
UTF-16LE no BOM    4100
UTF-16LE BOM       FFFE4100
UTF-16BE BOM       FEFF0041
```

修正後にVM KitをFresh生成し、C2正常系を最初から実行した結果が本Documentの正式Evidenceである。

---

## 9. Compatibility interpretation

C2正常系最終Runから次をBaselineとして扱う。

1. Original / ModernはACP932環境でCP932 Response Fileを同じInput Setとして解釈した。
2. UTF-8 BOMあり / なしをOriginal / Modernが同等に扱った。
3. UTF-16LE BOMあり / なし、UTF-16BE BOMありをOriginal / Modernが同等に扱った。
4. `CRLF` / `LF` / `CR`の3種類のNewlineでOriginal / Modern差を検出しなかった。
5. Command Line途中のSJIS → UTF-8切替、およびUTF-8 → bare `/cp` → SJIS resetがOriginal / Modernで一致した。
6. `/@`保持と`/$`削除のResponse File lifetime behaviorが一致した。
7. 正常系11 CaseすべてでModern-only regression、Crash、unexpected external state changeを検出しなかった。
8. Final Classificationは`MATCH`で、Generated ZIP byte SHA-256も11 / 11 pair一致した。

これは現在のLegacy parser behaviorを固定するRegression Baselineであり、Invalid byte sequenceに対する安全性や将来のFilename Decode設計を保証するものではない。

---

## 10. Local evidence and freeze point

Formal RunではVM Kit内に次を生成した。

```text
evidence-response\state-before.json
evidence-response\original-result.json
evidence-response\modern-result.json
evidence-response\comparison.json
```

この4 Fileを次のLocal Evidence ArchiveとしてFreezeした。

```text
poc2-c2-normal-evidence.zip
SHA-256:
679d13c404d174c31c2013f3e62b2e937abbb2f1ecc88d2b44c516a3f7a4ff69
```

Local EvidenceはVM / Binary / Local Pathを含むためRepositoryへそのままCommitせず、必要なIdentityと結論を本Documentへ転記する。

本ResultはRepository HEAD `ef915cad9913582f42bdd737d33104c4e77dd1b8`の正常系BaselineとしてFreezeする。後続Tooling変更がこのHistorical Evidenceを遡って変更することはない。別HEADで正常系を再証明する必要が生じた場合は、新しいEvidenceとしてFresh Runする。

---

## 11. Normal baseline decision

PoC 2-C2の**正常系BaselineはComplete / MATCH**とする。

正常系EvidenceはRepository HEAD `ef915cad9913582f42bdd737d33104c4e77dd1b8`のHistorical BaselineとしてFreezeし、Abnormal Caseでは正常系を再実行せず、別Fixture / Result / Evidence Directoryへ分離した。

Abnormal Caseでは「Originalと同じなら常に正しい」とは扱わず、Legacy behaviorのうち安全性上維持すべきでないものは`SECURITY_CHANGE_REQUIRED`として分類する方針を採用した。

---

## 12. Abnormal scope and matrix

Abnormal Caseは2026-08-23に次の7 Caseで実行した。

```text
invalid-cp-value
invalid-cp-syntax
invalid-utf8-at
invalid-utf8-dollar
utf16le-lone-surrogate-at
utf16le-odd-at
utf16be-odd-at
```

最初の5 CaseはSource archaeologyからExpected behaviorを事前固定した`asserted` Case、odd-length UTF-16LE / BEの2 Caseは境界依存挙動を決め打ちしない`observe-only` Caseとした。

Invalid `/cp` Caseは、valid direct inputをInvalid switchより前へ置き、`ParseCommandLine()`が`PROCESS_INVALID`を返した後に`main()`がEmpty `FileList`を理由としてConfiguration Dialogへ置換する経路を避けた。Response File argumentはInvalid switchより後へ置き、ParserがResponse Fileを読まずに停止することを分離確認した。

Abnormal Fixture / Evidenceは正常系と分離した。

```text
fixture-response-abnormal
original\response-abnormal-results
modern\response-abnormal-results
evidence-response-abnormal
```

---

## 13. Abnormal fixed environment and identity

Formal Abnormal VM KitはRepository HEAD `d1e28e1c75399ea8ce6f187d0329e50a9e519c0d`から生成した。

```text
VM Kit ZIP SHA-256
00b53a515d08badf6da369fb1f12ba6408396674068c5d150733b3d4dbefb8ab

Windows PowerShell
5.1.26100.8875 / Desktop

CLR
4.0.30319.42000

ANSI Code Page
932

Culture / UICulture
ja-JP / ja-JP

OS
Microsoft Windows NT 10.0.26200.0
```

Target identity:

```text
Original LhaForge.exe
SHA-256: 7326c767fe308f03bfb61ac15b9ba97be43385877667e63751e5962d8b2ac846
Size:    1,001,984 bytes
PE:      0x014c / x86
Version: Ver.1.6.7

Modern LhaForge.exe
SHA-256: 7d3bc5db76618709e7518badb649fcf6b1606567397034265ac330e10837dff7
Size:    1,049,088 bytes
PE:      0x014c / x86
Version: Ver.1.6.7

7-ZIP32.DLL
SHA-256: a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c
Size:    640,512 bytes
PE:      0x014c / x86
Version: 9.22.0.2
```

Initializer / Runner / Capture / Compareは各段階でWindows PowerShell 5.1、ACP932、local fixed disk、ASCII-only Kit Path、Target EXE / DLL identityを再確認した。

---

## 14. Abnormal result

Asserted Case result:

| Case | Original | Modern | Response post-state | Behavior signature |
| --- | --- | --- | --- | --- |
| `invalid-cp-value` | expectation MATCH | expectation MATCH | preserved | `7613d4f6c3cebe646add42d3a4b02d07eac1f8d2e3b6880969a9199890a86931` |
| `invalid-cp-syntax` | expectation MATCH | expectation MATCH | preserved | `7613d4f6c3cebe646add42d3a4b02d07eac1f8d2e3b6880969a9199890a86931` |
| `invalid-utf8-at` | expectation MATCH | expectation MATCH | preserved | `d1fd1bd0eb0000237a06cd6f64d7e6ecd5a667843d31d8895734663d27ef9411` |
| `invalid-utf8-dollar` | expectation MATCH | expectation MATCH | deleted | `47bf2df74e6d42fd11b537812ea8ab7e590aaccceb0ff953d82e372c36851205` |
| `utf16le-lone-surrogate-at` | expectation MATCH | expectation MATCH | preserved | `cc184afecdfacc19d8ccd7e701646ba38395a8808e152a5a2682099e443ebf5a` |

Observe-only result:

| Case | Original signature | Modern signature | Observation |
| --- | --- | --- | --- |
| `utf16le-odd-at` | `0d230cb8cfae32b7a17022954c4f47b3c2053e214beec430d2f80bd36e7ed410` | `0d230cb8cfae32b7a17022954c4f47b3c2053e214beec430d2f80bd36e7ed410` | parity; File-not-found Dialogで`A`がPathとして観測された |
| `utf16be-odd-at` | `9912107e02a75a1f52952554fd71c07a35d201f79cbbcc5e8b2d27a36115b223` | `9912107e02a75a1f52952554fd71c07a35d201f79cbbcc5e8b2d27a36115b223` | parity; endian-swap後の崩れた短いPathが観測された |

全14 Runについて次を確認した。

- Process Exit Code: `0`
- Timeout: none
- Crash-like exit: none
- Generated Archive: none
- Dialog observation: yes
- `/@` Response working copy: byte-identical preserved
- `invalid-utf8-dollar`の`/$`: deleted
- External AppData / ProgramData state: initializationからunchanged
- tracked `%TEMP%\zip*.tmp` state: initializationからunchanged
- Normal C2 fixture / evidence directories: untouched

Invalid UTF-8は`MultiByteToWideChar(CP_UTF8, 0, ...)`経路でConversion Failureとして停止せず、Replacementを含む存在しないPathとして後段Path validationへ到達した。`/@`ではResponse Fileを保持し、`/$`ではResponse read成功直後に削除された後でPath validationが失敗するLegacy lifetime behaviorをOriginal / Modern双方で確認した。

Final Compare:

```text
[POC2-RSP-ABN] Classification: SECURITY_CHANGE_REQUIRED
[POC2-RSP-ABN] OBS: Observe-only case utf16le-odd-at: Original signature 0d230cb8cfae32b7a17022954c4f47b3c2053e214beec430d2f80bd36e7ed410; Modern signature 0d230cb8cfae32b7a17022954c4f47b3c2053e214beec430d2f80bd36e7ed410.
[POC2-RSP-ABN] OBS: Observe-only case utf16be-odd-at: Original signature 9912107e02a75a1f52952554fd71c07a35d201f79cbbcc5e8b2d27a36115b223; Modern signature 9912107e02a75a1f52952554fd71c07a35d201f79cbbcc5e8b2d27a36115b223.
[POC2-RSP-ABN] OBS: Source-level safety hardening is required for: utf16le-odd-at, utf16be-odd-at.
```

`comparison.json`は`issueCount: 0`、`caseCount: 7`を記録した。

---

## 15. Security interpretation

`SECURITY_CHANGE_REQUIRED`はModern x86にRegressionが見つかったという意味ではない。

Original / ModernのBehavioral Parityは7 / 7 Caseで成立した。一方、odd-length UTF-16LE / BEではResponse Readerが奇数byte長を事前Rejectせず、Legacy `WCHAR*`解釈 / endian-swap経路へ渡す。実測でもLE / BEで境界依存の短いPath解釈が観測された。

この挙動は**Legacy compatibility requirementとして保存しない**。Production modernizationでは、UTF-16 Response Fileについて少なくとも奇数byte長をConversion前にDeterministicにRejectし、Malformed inputとして明示的に扱うSource-level hardening requirementへ引き継ぐ。

PoC 2-C2の目的はLegacy Baselineの固定であるため、このHardening自体はC2へ混在させない。実装時にはOriginal parityを壊したRegressionではなく、Documented Security ChangeとしてTest Caseを継承する。

---

## 16. Abnormal local evidence and freeze point

Formal Abnormal Runでは次を生成した。

```text
evidence-response-abnormal\state-before.json
evidence-response-abnormal\original-result.json
evidence-response-abnormal\modern-result.json
evidence-response-abnormal\comparison.json
original\response-abnormal-results\run-records\...
modern\response-abnormal-results\run-records\...
fixture-response-abnormal\...
```

Canonical Local Evidence Archive:

```text
poc2-c2-abnormal-evidence-v2.zip
SHA-256:
99f0b50d02c7b485e343f60fe0913be2f272f3c8ee26d92436e77d4b374f8f61

Size:
52,656 bytes

ZIP entries:
73

Duplicate normalized member paths:
0
```

初回Evidence ArchiveはOriginal / Modern双方の`response-abnormal-results`を同じZIP root nameへ格納したためmember pathが重複し、Canonical Freezeには採用しなかった。v2では`original\...` / `modern\...`を明示分離し、payload identityを維持したままduplicate member pathを0にした。

Local EvidenceはVM / Binary / Local Pathを含むためRepositoryへそのままCommitせず、必要なIdentityと結論を本Documentへ転記する。

本Abnormal ResultはRepository HEAD `d1e28e1c75399ea8ce6f187d0329e50a9e519c0d`のHistorical BaselineとしてFreezeする。

---

## 17. Final C2 decision and next stage

PoC 2-C2は次の状態で**Complete**とする。

```text
Normal:
  Complete / MATCH

Abnormal:
  Complete / SECURITY_CHANGE_REQUIRED

Overall PoC 2-C2:
  Complete
```

正常系ではModern-only regressionを検出しなかった。AbnormalでもOriginal / Modern parityは成立したが、odd-length UTF-16のLegacy behaviorは互換要件として維持せず、明示的Validationを必要とするDocumented Security Changeとして引き継ぐ。

次はPoC 2-C3 ZIP Entry Name Metadata / Cross-platform oriented Fixtureへ進む。

PoC 2-C全体はC3 / C4完了まで`In progress`のままとする。
