# LhaForge v1.7.0 PoC 2-C3 Formal VM Kit Host Gate

- Status: **Complete / PASS**
- Validation date: 2026-08-30
- Runtime comparison status: **Pending**
- Tested repository HEAD: `1be78cd5e5e43bfb90c545998d3eee58f66271a1`
- Tested branch: `develop-v1.7.0`
- Formal VM Kit SHA-256: `31c31f0140003f1d47242244bd734d05f0248bf325c9ac3d3d5e93947f77c672`
- Historical ZIP backend: `7-ZIP32.DLL` 9.22.0.2 x86
- Historical backend SHA-256: `a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c`

Related documents:

- `regression-encoding.md`
- `regression-encoding-c3.md`
- `poc-plan.md`

Related tooling:

- `../../../tools/poc2-encoding-c3-host/generate-fixtures.ps1`
- `../../../tools/poc2-encoding-c3-host/validate-fixtures.ps1`
- `../../../tools/prepare-poc2-c3-regression.ps1`
- `../../../tools/validate-poc2-c3-vm-kit.ps1`
- `../../../tools/poc2-encoding-vm/C3-CHECKLIST.md`
- `../../../tools/poc2-encoding-vm/c3-common.ps1`
- `../../../tools/poc2-encoding-vm/initialize-c3-regression.ps1`
- `../../../tools/poc2-encoding-vm/run-c3-case.ps1`
- `../../../tools/poc2-encoding-vm/run-c3-target.ps1`
- `../../../tools/poc2-encoding-vm/capture-c3-result.ps1`
- `../../../tools/poc2-encoding-vm/compare-c3-results.ps1`

---

## 1. Purpose

このDocumentはPoC 2-C3のVM Runtime Resultではなく、VMへ持ち込むFormal KitをHost PC上で生成・検証した結果をFreezeする。

PoC 2-C3自体はまだCompleteではない。

現在のGateは次の位置にある。

```text
C3 Source archaeology
        PASS
          |
Deterministic raw ZIP fixture design
        PASS
          |
Host Generator / Independent Validator
        PASS
          |
Formal VM Runner / Evidence tooling
        PASS
          |
Formal VM Kit Host Gate
        PASS  <-- this document
          |
Original v1.6.7 VM runtime
        PENDING
          |
Modern x86 VM runtime
        PENDING
          |
Original / Modern comparison
        PENDING
```

したがって本Documentの`PASS`はApplication Behaviorの`MATCH`を意味しない。

---

## 2. Frozen Fixture Gate

Hostで15 Fixtureを再生成し、Independent Validatorを通した。

```text
Generator empty byte-array smoke test: PASS
Validator empty byte-array smoke test: PASS
Generated cases: 15
Independent validation: 15 / 15 PASS
```

Frozen Archive SHA-256:

| ID | SHA-256 |
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

Malformed / Conflict Fixtureも「正常化された結果」ではなく、意図したRaw Metadataが存在することをValidator側で確認済みである。

---

## 3. Host Build Gate

Formal Kit生成時にModern `Release|Win32`を再Buildした。

Observed environment:

```text
Visual Studio 2026 Community
Installation version: 18.8.12023.21

MSVC compiler family:
14.44.35207

Windows SDK:
10.0.26100.0

WTL:
9.1.5321
```

Result:

```text
Environment verification: PASS
Release|Win32 Build: PASS
LhaForge.exe output: PASS
```

Formal KitはTested HEAD `1be78cd5e5e43bfb90c545998d3eee58f66271a1`から生成したModern x86 Binaryを含む。

---

## 4. Fixed Historical Backend Gate

Original / Modernの双方へ同一Historical Backendを使用する。

```text
7-ZIP32.DLL
Version: 9.22.0.2
Architecture: x86
SHA-256:
a82d2b10960f9ebaf5b9d56e2f495c72c22f5de542740d585ab14cb0b291999c
```

PoC 2-C3 Runtime中にこのBackendを差し替えない。

このVersionはHistorical Regression用であり、v1.7.x Production Defaultを意味しない。

C3 Fixtureは後続PoC 4のOfficial `7z.dll` Backendでも再利用する。

---

## 5. Formal VM Kit

Final Host-validated Kit:

```text
.baseline\poc2-encoding\c3-vm-kit
.baseline\poc2-encoding\poc2-c3-vm-kit.zip
```

Frozen identity:

```text
Repository HEAD:
1be78cd5e5e43bfb90c545998d3eee58f66271a1

VM Kit SHA-256:
31c31f0140003f1d47242244bd734d05f0248bf325c9ac3d3d5e93947f77c672

Fixture count:
15
```

Host Validator result:

```text
Formal VM kit Host validation: PASS
Fixtures: 15 / 15
PowerShell parser: PASS
Runtime helpers: PASS
ZIP duplicate paths: 0
ZIP unsafe paths: 0
```

このKitをPoC 2-C3 Formal VM Runtimeの入力としてFreezeする。

---

## 6. Host Tooling Failure Found Before VM

Runtime Helper Smoke Testを追加したことで、VM実行前に`0x7075` Extra Field ParserのWindows PowerShell 5.1互換性問題を検出した。

Failure signature:

```text
nameHex=93FA967B8CEA2E747874
extraHex=75700F0001B87EC365E588A5E5908D2E747874

cp932.valid=True
upath=NULL
candidate.count=1
candidate=raw-cp932
```

Fixture Validator側では同じArchiveについて、

```text
0x7075 version=1
nameCrcMatch=True
unicodeUtf8Valid=True
```

を確認していたため、Fixture不良ではなくRuntime Helper側のParsing defectとして切り分けた。

原因はLittle Endian `UInt16`をPowerShell 5.1で読む際に、`[byte]` operandを直接`-shl 8`していたことだった。

修正ではShift前に`[int]`へ昇格する`Get-C3UInt16Le`を導入し、Host Validatorで次をRuntime Smoke Testするようにした。

```text
0x7075 Extra Field ID decode
Extra Field Size decode
Unicode Path Parser non-null
Version == 1
strict UTF-8 == valid
Conflict candidate count >= 2
```

Parser Fix commit:

```text
1be78cd5e5e43bfb90c545998d3eee58f66271a1
Fix PoC 2-C3 extra field parsing
```

この修正後にFormal Kitを再生成し、Runtime Helper GateまでPASSした。

---

## 7. Discarded Pre-final Kit

Parser Fix前に生成した次のKitはFormal Runtimeへ使用しない。

```text
Repository HEAD:
a58e4369bf9122d108e53df9e5e0b00906dc80f9

VM Kit SHA-256:
0c93d949976c6b7a4e53e1d2f5c2143be196ba28332a71945b2ff797439ab190

Status:
DISCARDED
```

理由:

```text
C3 helper conflict candidate smoke test failed
```

Archive Fixture自体は15 / 15 PASSしていたが、Runtime Helper Gate未完了のためFormal EvidenceとしてFreezeしない。

---

## 8. Runtime Classification Policy

VM Runtime後のComparisonは次を使用する。

```text
MATCH
EXPECTED_DIFFERENCE
REGRESSION
SECURITY_CHANGE_REQUIRED
UNKNOWN
```

Automatic comparisonではClassごとの意味を分離する。

```text
spec-valid
cross-platform-observe
    Original / Modern difference
    -> REGRESSION candidate

legacy-observe
metadata-observe
conflict-observe
malformed-observe
    Original / Modern difference
    -> UNKNOWN / manual review first
```

Malformed / Conflict BehaviorがOriginalとModernで一致していても、それだけでProduction Compatibility Requirementとして保存しない。

Security / Correctness上保存すべきでないBehaviorはEvidence確認後に`SECURITY_CHANGE_REQUIRED`へ分類できる。

---

## 9. VM Runtime Order

次回以降、Formal KitをVMのLocal Fixed DiskへCopyして展開する。

VM内では既存の`C3-CHECKLIST.md`をPrimary Procedureとする。

Execution order:

```text
1. initialize-c3-regression.ps1

2. run-c3-target.ps1 -Target original
3. capture-c3-result.ps1 -Target original

4. run-c3-target.ps1 -Target modern
5. capture-c3-result.ps1 -Target modern

6. compare-c3-results.ps1
```

各Caseは次の順で実行する。

```text
List
Test
Extract
```

15 FixtureをOriginal / Modernへ同一順序で実行する。

---

## 10. Runtime Stop Conditions

次の場合は後続Caseへ進まず、最初のEvidenceを保存して原因調査する。

- Process crash / access violation
- Fixture SHA-256 mismatch
- Backend SHA-256 / Architecture mismatch
- Wrong-directory extraction
- Fixture以外のFile deletion / overwrite
- Unexpected AppData / ProgramData mutation
- Security-relevant behavior
- Modern-only unexpected behavior

Malformed FixtureでArchive Errorになること自体はStop理由にしない。

各Operation後のExternal AppData / ProgramData差分はRunner側でも確認し、Unexpected mutation検出時はRun Recordを保存した上で停止する。

---

## 11. Freeze Rule

このFormal Kitは次の条件が成立する限り再生成しない。

```text
C3 Fixture unchanged
C3 Runtime tooling unchanged
Historical backend unchanged
Modern tested source/tooling unchanged
```

Documentation-only commitが後から追加されても、Tested HEAD `1be78cd5e5e43bfb90c545998d3eee58f66271a1`とKit SHA-256を保持し、単にBranch HEADが進んだという理由だけでは再生成しない。

次の場合はFormal Kitを再生成し、新しいSHA-256をFreezeする。

- C3 Fixture Generator / Validator変更
- C3 Runtime Runner / Helper / Comparator変更
- `prepare-poc2-c3-regression.ps1`変更
- Formal Kit Validator変更
- Modern executableに影響するSource / Build変更
- Historical backend変更

再生成した場合、旧Kitを新しいFormal Evidenceと混在させない。

---

## 12. Current Boundary

2026-08-30時点:

```text
PoC 2-C1
  Complete / MATCH

PoC 2-C2
  Complete
  Normal: MATCH
  Abnormal: SECURITY_CHANGE_REQUIRED

PoC 2-C3
  Host Fixture Gate: PASS
  Formal VM Tooling: PASS
  Formal VM Kit Host Gate: PASS
  Original Runtime: PENDING
  Modern Runtime: PENDING
  Runtime Classification: PENDING

PoC 2-C4
  Planned
```

次に必要な作業はHost側の追加実装ではなく、Freeze済みFormal Kitを使用したVM Runtimeである。
