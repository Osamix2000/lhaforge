# LhaForge v1.7.0 Performance Design

* Status: Draft
* Target: LhaForge v1.7.x
* Scope: Archive Operation / Backend Selection / LegacyHost / UI / File Enumeration

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

v1.6.7実動環境を可能な範囲でReferenceとして比較する。

## 12. Metrics

候補:

* Wall-clock time
* CPU time
* Peak working set
* Disk read / write量
* Temp disk usage
* Entry throughput
* IPC message count / size
* UI progress update count

## 13. Open Items

* Benchmark dataset
* Default concurrency
* Capability Cache invalidation方式
* Built-in Backend libraryごとのThreading Policy
* File Enumeration API
* Long path handlingによるPerformance影響
