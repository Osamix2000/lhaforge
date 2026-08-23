# LhaForge v1.7.0 Performance Design

* Status: Draft
* Target: LhaForge v1.7.x
* Scope: Archive Operation / Backend Selection / LegacyHost / UI / Settings / Idle Runtime / File Enumeration

## 1. Principle

PerformanceはSecurityやCorrectnessを省略して得るものではなく、必要なValidationを維持した上で無駄なI/O、Copy、Scan、IPC、UI更新を減らすことで改善する。

最適化は計測結果に基づいて行い、Legacy Behaviorを壊す危険なMicro Optimizationを先行させない。

## 2. Operation Planning

圧縮時のDirectory Tree列挙、除外判定、Security Checkを可能な限り一つのPlanning Flowへまとめる。

```text
Enumerate once
    ↓
Normalize / Filter / Validate
    ↓
Final Input Plan
    ↓
Backend
```

同じTreeを設定ごと・Backendごとに繰り返しScanしない。

## 3. Exact Input Set

除外付き圧縮ではFinal Input SetをBackendへ効率よく渡す。

優先:

1. Backend APIのFile List / Include List
2. Response File等のBackend対応機構
3. Adapterによる効率的なBatch入力

全対象をTemporary DirectoryへCopyする方式は、I/O・Disk容量・時間の負担が大きいため原則採用しない。

## 4. Memory Usage

大量Fileを扱う場合も、不要に全Metadataを複数Copyしない。

* Bounded buffers
* Batch processing
* Move / referenceの活用
* 必要時のみ詳細Metadata取得
* UI表示用ModelとBackend用Dataの重複削減

ただしLifetimeやThread Safetyを犠牲にしない。

### 4.1 Idle / UI Lightweight Policy

Archive圧縮・展開中のMemory UsageはBackend / Codec / Input Size / Threading等のOperation条件へ依存するため別途Budgetする。一方、Archive Operationを行っていない通常Runtimeでは、v1系の軽快さを継承し、不要なResourceを常駐させないことを明示的なGoalとする。

対象Scenario:

```text
Cold start
Idle
Settings open
Settings close
Archive list open / close
Operation completed -> Idle
```

原則:

* Archive Backend DLLは必要になるまでLoadしない
* x86 LegacyHostはLegacy x86 Backendを実際に利用するまで起動しない
* 設定画面を開くだけで全BackendをLoad / Probeしない
* Backend / Dependency更新確認の常駐ThreadやBackground Pollingを設けない
* 設定Page / Dialog / large modelは必要時に生成し、不要後にReleaseする
* Cacheはbounded / invalidatableとし、無制限成長させない
* Operation固有Buffer / Entry Metadata / temporary objectを処理完了後に保持し続けない
* Timer / Watcher / Worker Threadを常時起動する場合は明確な必要性と計測Evidenceを要求する

Working SetはWindowsのPaging / File Cache等で変動するため、見かけ上のWorking Setを強制Trimすること自体を最適化Goalにしない。Private Bytes / Private Commit、Handle、Thread、Module、GDI / USER Object等も合わせて計測し、実際に不要なAllocation / Lifetimeを減らす。

Exact numeric budgetは現時点で固定せず、v1.6.7 BaselineとModern x86 / x64実測後に設定する。最低条件として、Settings open/closeやOperation反復でPrivate allocation / Handle / Threadが無制限に増加しないことを要求する。

## 5. LegacyHost IPC

Archive Data本体はNamed Pipeへ流さない。

IPCはControl / Metadataを中心とし、大量ListはBatch送信する。

必要に応じてLegacyHostをApplication Session中再利用し、Process Startup / DLL Initialization costを抑える。

異常状態のHostは再利用しない。

## 6. Backend Discovery Cache

DLLのArchitecture、Version、Export、Capability等は毎Operationで高コスト検査を繰り返さないようCache可能とする。

ただしユーザーがDLLを手動差し替えできるため、File timestamp / size / identity等によるInvalidationが必要である。

Security上必要なValidationを永久Cacheしない。

## 7. UI Responsiveness

長時間処理はUI ThreadをBlockしない。

Progress更新は過剰頻度にしない。

* Batch update
* Throttle
* Cancellation responsiveness
* 大量ListのVirtualization / Lazy rendering検討

File数が多い場合に1Entryごとに重いUI処理を行わない。

## 8. File I/O

* Sequential I/Oを活かす
* 不要なRead-backを避ける
* Temp fileの生成を必要最小限にする
* 同一Volume内Rename等、安価な操作を利用可能なら優先する
* Small file大量処理とLarge file処理を区別して計測する

## 9. Concurrency

ParallelismはBackend、Storage、CPU、Operation内容に応じて利用する。

Thread数を無制限に増やさない。

Legacy DLLがThread-safeとは限らないため、Capability / Backend PolicyとしてConcurrency制限を持てるようにする。

## 10. Security Validation Cost

Path Validation、Resource Budget、Hash等のSecurity処理は省略しない。

ただし、同一Operation内で同じCanonicalizationやFile Statを複数Layerが重複実行しないよう、Validation結果を明確なData構造で引き渡す。

Trust Boundaryを越えた場合は必要に応じて再検証する。

## 11. Benchmarks

Build Modernization後、少なくとも次のBenchmarkを作成する。

* Small files大量圧縮 / 展開
* Large single file圧縮 / 展開
* Deep directory tree
* Exclusion Rule多数
* `.git`等を含むRepository tree
* LegacyHost x86 Backend
* External x64 Backend
* Built-in Backend
* Archive list表示
* Cold start / Idle
* Settings open / close / repeated open-close
* Operation完了後のIdle回復

v1.6.7実動環境を可能な範囲でReferenceとして比較する。

## 12. Metrics

候補:

* Wall-clock time
* CPU time
* Peak working set
* Private Bytes / Private Commit
* Idle working set / private memory
* Handle count
* Thread count
* Loaded module count
* GDI / USER object count where applicable
* Disk read / write量
* Temp disk usage
* Entry throughput
* IPC message count / size
* UI progress update count

## 13. Zstandard Performance Profile

ZstandardのLhaForge既定値はCompression Level 22 (Ultra)とする。

```text
Level: 22
Thread policy: Auto / Performance
--max equivalent: OFF
```

Zstd v1.5.7のCLIでは`--ultra`が20以上のLevelを解禁し最大22まで利用できる。`--max`はLevel 23ではなく、最大Compressionを狙ってAdvanced Parameterを変更する別Presetである。

`Auto / Performance`はWorker数を最大値へ固定するのではなく、Level 22を維持した上でWall-clock timeを短縮することを目的とする。

Zstd LibraryのMulti-thread CompressionではWorker数を増やすとMemory Usageが増加する。またJob overlapはCompression RatioとSpeedに影響する。そのため次をBenchmarkしてDefault Heuristicを決定する。

* Physical Core基準
* Logical Processor基準
* Input Size別Worker数
* Small file / Large stream
* Memory量別上限
* SSD / slower storage
* Zstd Level 22でのJob overlap
* `.zst` vs `.zste` Pipeline overhead

CLIの`-T0`相当はPhysical Core検出をBaseline候補とするが、LhaForge Built-in BackendではRuntimeのCPU / Memory / Input条件を考慮して最終Worker数を決める。

Compression Level自体を動的に変更する`--adapt`は、Level 22固定というDefault Policyには使用しない。

### Maximum Compression

`--max`相当はAdvanced Optionとする。

* Default OFF
* 64-bit Built-in Backendを基本対象
* Large memory / long runtime warningをUIへ表示
* Confirmation dialogは要求しない
* Pinned Zstd Version更新時にBenchmark / Regressionする

Zstd v1.5.7 Release Noteでは`enwik9`の例で`--max`が`--ultra -22`より高いCompression Ratioを得る一方、Time / Memory Costが大幅に増えることが示されている。

`--max`は大きなWindow等を選択し得るため、圧縮時だけでなく展開時のMemory Requirementも増える可能性がある。生成Frameは標準Zstandardだが、Decoder側のResource Policy / Memory LimitによってはDefault設定で拒否され得るため、Compatibility / Resource Budget Testへ含める。

---

## 14. Open Items

* Benchmark dataset
* Default concurrency
* Capability Cache invalidation方式
* Built-in Backend libraryごとのThreading Policy
* Zstd Auto / Performance Worker heuristic
* Zstd `--max`相当PresetのPinned Version追従方式
* File Enumeration API
* Long path handlingによるPerformance影響
* v1.6.7 / Modern x86 / x64のIdle・Settings Memory baseline
* Settings close / Operation完了後のResource return threshold
