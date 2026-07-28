# ADR-0003: x64本体とLegacyHostを採用する

* Status: Accepted
* Target: LhaForge v1.7.x
* Related:

  * ADR-0002: v1系外部DLL互換を維持する
  * ADR-0004: Built-in BackendをFallbackとして持つ

## Context

LhaForge v1.6.7本体は32bitアプリケーションとして動作している。

v1.7.xでは現代のWindows環境を主対象とするため、LhaForge本体を64bit化する。

一方、v1系で利用されてきた統合アーカイバDLLの中には、現在でも32bit版しか存在しないものがある。

Windowsでは64bitプロセスから32bit DLLを直接LoadLibraryすることはできない。

そのため、本体を64bit化するだけではv1系外部DLL互換を維持できない。

## Decision

LhaForge v1.7.xでは、

```text
LhaForge.exe
    x64

LhaForgeLegacyHost.exe
    x86
```

という構成を採用する。

x64版が利用可能な外部DLLはLhaForge本体から直接利用する。

x86版しか利用できない外部DLLについては、32bitの`LhaForgeLegacyHost.exe`からロードする。

```text
LhaForge.exe (x64)
       │
       ├─ x64 DLL
       │     ↑
       │     └─ 直接利用
       │
       └─ IPC
             │
             ↓
     LhaForgeLegacyHost.exe (x86)
             │
             ↓
          x86 DLL
```

## LegacyHostの責務

LegacyHostはArchive Applicationではなく、32bit DLLとのCompatibility Bridgeとする。

担当する処理は必要最小限とする。

例:

* DLLロード
* DLL API呼び出し
* Archive Open
* List
* Test
* Extract
* Create
* Update
* Delete
* Progress取得
* Error取得
* Capability確認

LhaForge本体が持つUI、設定、Backend選択、Security PolicyなどをLegacyHost側へ複製しない。

## IPC

LhaForge本体とLegacyHost間の基本IPCにはNamed Pipeを利用する。

IPCでは主として制御情報を送受信する。

例:

```text
Operation
DLL Path
Archive Path
Output Path
Options
Password metadata
Progress
Result
Error
File List
```

Archive本体のデータをIPC経由でストリーミングする設計は採用しない。

LegacyHostおよびx86 DLLは、必要なArchive/Input/Outputファイルへ直接アクセスする。

```text
LhaForge.exe
     │
     │ 制御情報
     ▼
Named Pipe
     │
     ▼
LegacyHost
     │
     │ File I/O
     ▼
Filesystem
```

これにより、大容量Archiveの処理でIPCがボトルネックになることを避ける。

大量の一覧情報など、IPCメッセージが大きくなる場合はBatch送信を基本とする。

必要性が確認された場合はShared Memory等の利用を検討する。

## Process Lifetime

LegacyHostはArchive操作ごとに毎回起動する設計に限定しない。

起動コストやDLL初期化コストが問題になる場合は、LhaForgeセッション中にLegacyHostを維持することを許容する。

ただし異常終了したLegacyHostを再生成できる構造とする。

LegacyHostのCrashがLhaForge本体のCrashへ直接波及しないよう、Process Boundaryを活用する。

## Backend Selection

ArchitectureによってBackendの優先順位を変えない。

基本順序:

1. 利用可能なx64外部DLL
2. 利用可能なx86外部DLL + LegacyHost
3. Built-in Backend
4. Error

x86 DLLであっても、CapabilityやCompatibilityの面で適切なBackendであれば利用する。

## Security

LegacyHostは外部DLLをロードするため、明確なSecurity Boundaryとして設計する。

少なくとも次を行う。

* LhaForgeが指定したDLLのみロードする
* DLL Pathを絶対パスで扱う
* Architectureを事前確認する
* DLL Search Pathを制限する
* IPC相手をLhaForgeプロセスに限定する
* 不正なIPC入力を検証する
* Archive Path等を正規化する
* Security PolicyはLhaForge本体側で決定する
* DLLから返されたPathやMetadataを信頼しない

LegacyHostを導入することをSandboxとみなしてはならない。

Legacy DLL自体の脆弱性や制約は残る。

## Error Handling

LegacyHostまたはDLLで障害が発生した場合は、LhaForge本体へ明確な結果を返す。

例:

```text
HostStartFailed
PipeConnectionFailed
DllNotFound
DllArchitectureMismatch
DllLoadFailed
ApiNotFound
UnsupportedVersion
OperationFailed
HostCrashed
Timeout
```

失敗時にBuilt-in BackendへFallbackできる場合はFallbackを検討する。

ただし、Extract/Create等で既にファイルを書き換えた後に別Backendへ自動再試行するとデータの二重生成や破損が発生する可能性がある。

そのためFallbackの可否は操作段階を考慮して判断する。

## Logging

LegacyHost関連LogはLhaForge共通Logging Infrastructureへ集約する。

Componentとして少なくとも次を識別可能にする。

```text
LegacyHost
LegacyHost.IPC
LegacyHost.DLL
```

LegacyHost内部のDebug/Trace情報も、必要に応じてLhaForge側のFile LogおよびWindows Event Logへ統合する。

## Consequences

### Positive

* LhaForge本体をx64化できる
* x86専用Legacy DLLを継続利用できる
* Legacy DLLのCrashを本体プロセスから分離できる
* 将来x64 DLLへ段階的に移行できる
* 大容量ArchiveをIPCへ流す必要がない

### Negative

* x86/x64両方のBuildが必要になる
* IPC Protocolの設計・Version管理が必要になる
* Process間Error Handlingが必要になる
* LegacyHostの配布・更新が必要になる
* Debugが単一Processより複雑になる

## Alternatives Considered

### LhaForge本体を32bitのまま維持する

採用しない。

Legacy DLLとの互換性は高いが、v1.7.xを現代化する目的と矛盾する。

### x86 DLLの対応を廃止する

採用しない。

v1系外部DLL互換を維持する方針に反する。

### x64版とx86版のLhaForge本体を両方配布する

原則採用しない。

UI・設定・Shell Integration等を含むApplication全体を二重管理する必要があり、保守コストが大きい。

本体はx64へ統一し、x86互換性だけをLegacyHostへ限定する方が責務が明確になる。

## Notes

LegacyHostの目的はLegacy DLLを永久に維持することではない。

対応するx64 DLLが利用可能になった場合はx64版を優先し、LegacyHostの利用範囲を徐々に減らせる設計とする。
