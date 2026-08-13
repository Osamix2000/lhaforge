# PoC 2-C1 Direct Unicode Path Regression Result

- Status: **Complete / MATCH**
- Executed: 2026-08-13
- Scope: Original LhaForge v1.6.7 vs Modern x86 Release
- Tested repository HEAD: `1be80998f13d3a90952d95084ec7adbc332be3cc`
- Development branch: `develop-v1.7.0`
- Fixed backend: `7-ZIP32.DLL` 9.22.0.2 / x86
- Fixed backend SHA-256: `a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c`

Related documents:

- [PoC 2-C Encoding / Path Regression Plan](regression-encoding.md)
- [Regression Baseline](regression-baseline.md)
- [PoC Plan](poc-plan.md)
- [PoC 2-B Archive Basic Operation Regression](regression-archive.md)

---

## 1. Purpose

PoC 2-C1では、x64化やFilename Decode LayerのProduction実装へ進む前に、Original v1.6.7とModern x86がDirect Unicode PathとUnicodeを含むZIP roundtripを同じように扱うかを固定Backend / Deterministic Fixtureで比較した。

このStageでは新しいFilename Decode、Manual Encoding Override、Extraction Preview、Extraction Filter等は実装しない。

---

## 2. Fixed environment and evidence identity

最終Runで使用した主要Identity:

```text
Repository HEAD
1be80998f13d3a90952d95084ec7adbc332be3cc

VM Kit ZIP SHA-256
7c6f465596ec53c2230bd85fa837785736a70412e04cc67a0de3a65f64960f91

7-ZIP32.DLL
Version: 9.22.0.2
PE:      0x014c (x86)
SHA-256:
a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c

Reference Unicode ZIP SHA-256
9525daaa6272f7d01822b82690bc57e49811a1640f6d35b0b7126e65f50287b2

Path Probe ASCII-only ZIP SHA-256
8197def69a0866df3ab7759ad65566a48d12f32add63c37f032b39f182b72e63

Path Probe expected fingerprint
9dd20284771185e01f42c86591c13f17f557ada98c28570811139eea0624cf09

Original / Modern generated Unicode roundtrip ZIP SHA-256
bf004bef11435b0176dd7511319f79695e6e4568f1519a904e9258ac4788c673
```

VM-side regression tooling runtime:

```text
Windows PowerShell 5.1.26100.9168
PSEdition: Desktop
CLR: 4.0.30319.42000
```

Original / Modernは同一byte列の`7-ZIP32.DLL`を使用した。

---

## 3. Fixture design

### 3.1 Reference Unicode Fixture

List / Test / Compress / Re-extract用Fixtureは次の主要Name categoryを含む。

```text
ASCII
Japanese
Emoji
Supplementary Plane
Combining Character
NFC
NFD
```

初期化時のFixture inventory:

```text
files: 8
directories: 7
```

### 3.2 Direct Path Probe Fixture

Direct Pathだけを測定するため、Path Probe専用ZIPの内部Entry Name / PayloadはASCII-onlyへ固定した。

```text
pathprobe-reference.zip
`-- probe.txt
```

各Caseでは同一byte列のZIPを使用し、変化させるのは次だけとした。

```text
Archive File Name
Output Directory Name
```

これにより、ZIP内部Entry NameのUnicode処理をDirect Path判定から分離した。

実施Case:

```text
ascii
japanese
emoji
supplementary
combining
nfc
nfd
```

`Long Unicode path within current baseline limits`はこのC1最終Runでは独立Caseとしては実施していない。必要なDeep / Long Path境界試験はPath Security / x64 migration側の追加Regressionと分離する。

---

## 4. Procedure

OriginalとModernで同じ順序を実行した。

```text
List
Test
Path Probe: ascii
Path Probe: japanese
Path Probe: emoji
Path Probe: supplementary
Path Probe: combining
Path Probe: nfc
Path Probe: nfd
Compress
Re-extract
Capture
```

各TargetのRun record数:

```text
Original: 11
Modern:   11
```

最後に`compare-encoding-results.ps1`でOriginal / Modern Evidenceを比較した。

---

## 5. Result

### 5.1 Original

```text
List                         PASS
Test                         PASS
Path Probe / ascii           PASS
Path Probe / japanese        PASS
Path Probe / emoji           PASS
Path Probe / supplementary   PASS
Path Probe / combining       PASS
Path Probe / nfc             PASS
Path Probe / nfd             PASS
Compress                     PASS
Re-extract                   PASS
Capture                      PASS
```

### 5.2 Modern

```text
List                         PASS
Test                         PASS
Path Probe / ascii           PASS
Path Probe / japanese        PASS
Path Probe / emoji           PASS
Path Probe / supplementary   PASS
Path Probe / combining       PASS
Path Probe / nfc             PASS
Path Probe / nfd             PASS
Compress                     PASS
Re-extract                   PASS
Capture                      PASS
```

Final comparison:

```text
[POC2-ENC] Classification: MATCH
[POC2-ENC] OBS: Compressed ZIP byte SHA-256 is identical.
```

Original / Modernが生成したUnicode roundtrip ZIPは、最終Runではbyte SHA-256も一致した。

ただしPoC 2-Bと同様、Binary ZIP hash一致はPrimary compatibility criterionへ昇格しない。Filename semantics、Payload、Re-extract fingerprintをPrimary Evidenceとする。

---

## 6. Compatibility interpretation

C1最終Runから次をBaselineとして扱う。

1. Original / Modernとも、試験したJapanese / Emoji / Supplementary Plane / Combining / NFC / NFDを含むArchive File PathとOutput Directory Pathを処理できた。
2. List / TestはReference Unicode ZIPでOriginal / ModernともPASSした。
3. Unicodeを含むSource Directory Path / generated ZIP File Name / Entry Nameを使ったCompressがOriginal / ModernともPASSした。
4. 生成ZIPをUnicodeを含むOutput DirectoryへRe-extractし、Fixture fingerprintと一致した。
5. C1範囲ではModern-only regressionを検出しなかった。
6. Comparisonは`MATCH`で、Original / Modernの生成ZIP byte SHA-256も最終Runでは一致した。

これはLegacy Backendを含む現在BehaviorのRegression Baselineであり、将来のFilename Decode / Manual Override / Built-in Backend設計を不要とする結論ではない。

---

## 7. Tooling corrections discovered during C1

C1実行中に2件のRegression Harness問題を検出し、Product regressionと分離して修正した。

### 7.1 Windows PowerShell 5.1 UTF-8 JSON read

最初のVM Runでは、BOMなしUTF-8で保存したJSONをWindows PowerShell 5.1の`Get-Content`既定Encodingで読み、Unicodeを含むJSONがmojibakeして`ConvertFrom-Json`前後で失敗した。

これはLhaForge起動前のHarness failureであり、Original / Modern結果には分類しない。

修正:

```text
Commit:
fab83ca54c2a479dd410a63e422e497e9805b403

Fix UTF-8 JSON reads in PoC 2-C1 tooling
```

JSON readをstrict UTF-8の.NET APIへ統一した。

### 7.2 Direct Path Probe isolation

最初のPath Probe設計では、各Unicode Archive Pathへ`reference-unicode.zip`をそのままコピーしていたため、Archive File Path / Output Directory PathだけでなくZIP内部Unicode Entry Nameも同時に試験していた。

ASCII Caseを含む全Caseが同一actual fingerprintで失敗したため、Direct Path試験として変数分離できていないことを確認した。

これはC1 Direct PathのProduct failureとして採用せず、Path Probe専用ASCII-only ZIPへ分離した。

修正:

```text
Commit:
1be80998f13d3a90952d95084ec7adbc332be3cc

Fix PoC 2-C1 direct path probe isolation
```

修正後のFresh initializationからOriginal / Modern双方を再実行し、全Case PASS / final `MATCH`を得た。

---

## 8. Local evidence

VM Kit内で次を生成した。

```text
evidence\state-before.json
evidence\original-result.json
evidence\modern-result.json
evidence\comparison.json
```

各OperationのrecordはTargetごとの、

```text
original\results\run-records\
modern\results\run-records\
```

へ保存した。

これらはVM / Binary / Local Pathを含む実行Evidenceであるため、RepositoryへそのままCommitするDocumentではなく、必要なIdentityと結論を本Documentへ転記する。

---

## 9. Decision and follow-up

PoC 2-C1は**Complete / MATCH**とする。

C1ではProduction behaviorを変更せず、Original v1.6.7とModern x86のDirect Unicode Path / Unicode ZIP roundtripにModern-only regressionがないことをBaseline化した。

次はPoC 2-C2へ進み、Response File Encoding / BOM / Newline / `/cp:*`と`/@...` / `/$...`のLegacy parser behaviorをOriginal / Modernで比較する。

PoC 2-C全体はC2 / C3 / C4完了まで`In progress`のままとする。
