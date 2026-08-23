# ADR-0007: 公式Upstream優先とFormat別Backend Policyを採用する

* Status: Accepted
* Target: LhaForge v1.7.x
* Decision date: 2026-08-23
* Refines: ADR-0002 / ADR-0004および`backend.md`にある一律Backend Priority。`backend.md`のConcrete Backend Type / PackagingはPoC 4結果で同期する。
* Related:

  * ADR-0001: v1.6.7を開発基準とする
  * ADR-0002: v1系外部DLL互換を維持する
  * ADR-0003: x64本体とLegacyHostを採用する
  * ADR-0004: Built-in BackendをFallbackとして持つ
  * ADR-0005: 署名可能なRelease Architectureと最小権限設計を採用する
  * ADR-0006: 公開ZSTE FormatとAuthenticated Encryptionを採用する

## Context

LhaForge v1.7.xはLhaForge v1.6.7を直接の開発基準とし、統合アーカイバDLLとの互換性、LFCaldix、`cldx`等のv1系運用文化を維持しながらModernizeする。

一方、v1.6.7で主要ZIP / 7z Backendとして利用されてきた`7-ZIP32.DLL` 9.22.0.2はHistorical Compatibilityを測定する上では重要であるものの、Production Backendを将来にわたり同Versionへ固定する理由にはならない。

また、第三者がUpstreamを改良したFork / Private Buildは有用な場合があるが、Production Dependencyとして採用すると、Upstream更新に加えて独自変更、License、Supply-chain、Maintenance継続性を追加で追跡する必要がある。

LhaForge本体についても、Archive処理中だけでなくIdle、設定画面、通常UI等で不要なLibrary、Process、Thread、Cacheを常駐させず、v1系の軽快さを継承することを目標とする。

## Decision

### 1. Upstream First

Build-time / Runtime Dependencyは、必要な機能を公式Upstreamが満たせる場合、原則として公式UpstreamのStable Releaseを第一候補とする。

第三者Fork / 改良版 / Private Buildは、公式Upstreamでは満たせない具体的要件が確認された場合のみ採用候補とする。

例外採用時は少なくとも次をDocumentへ残す。

* 公式Upstreamでは満たせない要件
* 採用Fork / Version / Commit
* Upstreamとの差分
* License / redistribution確認
* Source audit結果
* Build reproducibility
* Security / regression結果
* Upstreamへ戻すためのExit条件

### 2. Release-coupled Dependency Update

Library単体の自動更新機構は導入しない。

LhaForge Release準備時に各Managed Dependencyの公式Upstream Stableを確認し、次のGateを通過した場合にLhaForge Releaseと合わせて更新する。

```text
Latest upstream stable candidate
        ↓
Release note / security review
        ↓
License / redistribution review
        ↓
API / ABI / build compatibility
        ↓
Regression / malformed input / performance test
        ↓
Version + SHA-256 pin
        ↓
LhaForge release
```

問題または未解決Riskがある場合は、無理に最新版へ更新せず直前のValidated Versionを維持する。

したがってLhaForgeが採用するのは単なるLatestではなく、**Latest Validated Stable**である。

### 3. 7-Zip Family

PoC 4以降のProduction Backend候補では、7-Zip公式Upstreamが配布する`7z.dll`を直接利用するFirst-party Adapterを標準経路の第一候補とする。

```text
LhaForge
   ↓
Official7ZipBackend
   ↓
official 7z.dll
```

`7z.exe`を子Processとして呼び出し、CLI outputを解析する方式は標準Backendとして採用しない。

公式`7z.dll`の具体的VersionはPoC 4開始時の最新Stable CandidateをLicense / API / Security / Regression Gateへ通した後にPinする。2026-08-23時点でProduction Versionは未固定である。

### 4. 7-ZIP32.DLL / Integrated Archiver Compatibility

`7-ZIP32.DLL`を含む統合アーカイバDLL互換は削除しない。

これはLhaForge v1系のCompatibility Featureとして正式に維持する。

7-Zip Familyでは、Official `7z.dll` BackendのPoC / Acceptance成立後、概念上次のPolicyを目標とする。

```text
Default / Recommended
    Official 7-Zip Library Backend

Legacy / Compatibility
    Integrated Archiver DLL Backend
    7-ZIP32.DLL
```

Option画面からLegacy方式を明示的に選択できる設計とする。最終UI文言はUI PoCで確定する。

User PreferenceはSecurity / Required Capabilityを上書きしない。

LFCaldix、`cldx`、他の統合アーカイバDLL Familyもv1系Compatibilityとして維持する。

### 5. Backend Priority is Format-specific

ADR-0002 / ADR-0004で定義した、

```text
External x64
→ External x86 + LegacyHost
→ Built-in
```

という一律Priorityは、Format / Operationを問わない最終Policyとしては採用しない。

互換性維持というADR-0002のDecision、およびBuilt-in可用性を持つというADR-0004のDecisionは維持するが、Default BackendはFormatごとのValidated Policyで決定する。

Selectionでは少なくとも次の順序を守る。

1. Security / Correctness Requirement
2. Required Format / Operation / Capability
3. Format-specific Default Policy
4. Explicit User Preference
5. Architecture / Performance Hint

7-Zip FamilyではOfficial `7z.dll` Backendを標準候補とし、Integrated Archiver `7-ZIP32.DLL`はLegacy / Compatibility選択肢とする。

他Formatでは、公式Upstream Managed Backendの有無、External DLL互換価値、Capability、Security、Performanceを個別評価する。

### 6. Historical Regression Backend

PoC 2-B / 2-Cで固定している`7-ZIP32.DLL` 9.22.0.2はHistorical Regression Backendとして維持する。

PoC 2-C3 / 2-C4もBaseline continuityを保つため9.22.0.2で完走する。

これはv1.7.x Production Backendを9.22.0.2へ固定するDecisionではない。

PoC 2-C3で作成するDeterministic Fixtureは、後続のOfficial `7z.dll` Backend検証でも再利用できるBackend-independent Evidence Assetとする。

### 7. Lightweight Runtime Policy

Compatibility Codeを保持することとRuntime Costを常時負担することを分離する。

原則:

* Archive Backend DLLは必要になるまでLoadしない
* x86 LegacyHostはLegacy x86 Backendを実際に利用するまで起動しない
* 設定画面を開くだけで全BackendをLoad / Probeしない
* Backend Updateのための常駐Thread / Background Pollingを設けない
* Cacheはbounded / invalidatableとし、無制限成長させない
* Dialog / Page / temporary modelは必要時に生成し、不要後にReleaseする
* Archive Operation終了後はOperation固有Buffer / large metadataを保持し続けない

Memory最適化はWorking Setを強制的にTrimして見かけの値だけを下げることではなく、不要なPrivate allocation、Commit、Handle、Thread、Object lifetimeを減らすことで行う。

## Consequences

### Positive

* 公式UpstreamのSecurity Fix / Format Fix / Windows対応を取り込みやすい
* 第三者ForkへのSupply-chain / Maintenance依存を減らせる
* LhaForge Release単位でDependency Versionを再現可能に固定できる
* v1系Integrated Archiver Compatibilityを失わない
* Official BackendとLegacy Backendを明示的に切り替えてTroubleshootingできる
* 使用しないLegacy BackendのRuntime Costを通常利用へ持ち込まない
* PoC 2 Historical Evidenceを将来Backend比較へ再利用できる

### Negative

* Official `7z.dll`用の新しいAdapter実装が必要になる
* v1.6.7の`7-ZIP32.DLL` APIを単純に置換するより改修範囲が大きい
* Backend selection / settings / diagnosticsの設計が増える
* Managed DependencyのReleaseごとのReview / Regression作業が必要になる
* External / Managed / LegacyのOwnership区分をInstaller / Repairへ反映する必要がある

## Alternatives Considered

### 7-ZIP32.DLL 9.22系をProductionでも継続する

採用しない。

Historical Regressionには必要だが、Productionの標準Backendを古いEngineへ固定する合理性がない。

### `7-zip32_ungarbled`等の第三者改良版を標準採用する

現時点では採用しない。

有力な参考実装 / 比較対象ではあるが、公式7-Zip Libraryで必要要件を満たせるかを先に検証する。公式Upstreamで不足が実証された場合に限り再評価する。

### `7z.exe`を標準Backendとして呼び出す

採用しない。

Process管理、Command Line / Response File、標準出力解析、Password、Progress、Cancel、Error Mapping等の追加境界が生じるため、Library APIを利用するAdapterを優先する。

### Integrated Archiver DLL互換を廃止する

採用しない。

LhaForge v1.6.7を基盤とするv1.7.xのCompatibility方針と一致しない。`7-ZIP32.DLL`を含むLegacy方式はOptionとして維持する。

## Follow-up

* PoC 2-C3 / 2-C4: `7-ZIP32.DLL` 9.22.0.2 Historical Baselineを完了する
* PoC 3: Actual x64 Main Applicationを成立させる
* PoC 4: Official `7z.dll` Adapterを最初のManaged x64 Backendとして検証する
* PoC 5: x86 Integrated Archiver DLLをLegacyHostで維持する
* Dependency Manifest: Official 7-Zip Version / SHA-256 / License / SourceをPoC 4開始時に固定する
* UI PoC: 7-Zip Backend Default / Legacy selectionの最終文言と配置を確定する
* Performance PoC: Idle / Settings / Post-operation Memory Budgetを測定してTargetを確定する
