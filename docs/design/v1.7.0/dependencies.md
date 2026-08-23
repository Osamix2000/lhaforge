# LhaForge v1.7.0 Dependency Management

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7
- Current implemented scope: Build-time WTL dependency
- Planned scope: Official Upstream Archive / Built-in Archive / ZSTE runtime dependencies

## 1. Purpose

LhaForge v1.6.7のBuild定義にはDeveloper Machine固有のWTL Include Pathが残っている。
v1.7.xでは、Build Dependencyを特定PCの手作業配置に依存させず、Version、取得元、IntegrityをRepositoryから再現可能にする。

このDocumentはBM-002のDependency Restore方針を定義する。


## 2. Upstream-first and release-coupled update policy

Runtime / Build Dependencyは、必要な機能を公式Upstreamが満たせる場合、公式UpstreamのStable Releaseを第一候補とする。第三者Fork / 改良版は、公式Upstreamでは満たせない具体的要件が確認された場合だけ例外候補とする。

Library単体の自動更新は行わない。LhaForge Release準備時に各Managed Dependencyの最新Stable Candidateを確認し、次を通過した場合のみLhaForge Releaseと合わせて更新する。

1. Official upstream / provenance確認
2. Release note / security issue確認
3. License / redistribution確認
4. API / ABI / compiler compatibility確認
5. Upstream test / LhaForge regression / malformed input test
6. Performance / Memory regression確認
7. Version / SHA-256 / Source URL / Notice固定

問題または未解決Riskがある場合は、直前のValidated Versionを維持する。採用対象は単なるLatestではなく`Latest Validated Stable`とする。

Third-party Forkを例外採用する場合は、Upstreamとの差分、採用理由、Source audit、Build reproducibility、License、Security / Regression結果、Upstreamへ戻すExit条件をDocument化する。

このPolicyはADR-0007でArchitecture Decisionとして固定する。

### Official 7-Zip direction

7-Zip Familyでは、PoC 4で7-Zip公式Upstreamの`7z.dll`を直接利用する`Official7ZipBackend`を検証する。`7z.exe`を子Processとして呼び出す方式は標準Backend候補としない。

Production VersionはPoC 4開始時にOfficial Stable Candidateを上記Gateへ通した後でPinする。PoC 2-B / 2-Cで利用している`7-ZIP32.DLL` 9.22.0.2はHistorical Regression Backendであり、Production Dependency Versionではない。

`7-zip32_ungarbled`等の第三者改良版は有用なReference / Comparison対象になり得るが、公式`7z.dll`で要件を満たせる限りProduction Dependencyへ優先採用しない。

---

## 3. Historical evidence and WTL version ambiguity

公式v1.6.7 Source Treeには、WTL Versionについて2種類のEvidenceが存在する。

`source.txt`:

```text
Microsoft Visual Studio 2017 Community
WTL 9.1 Final
```

`LhaForge/LhaForge.vcxproj`:

```text
ToolsVersion = 15.0
ProjectFileVersion = Visual Studio 2017 generation
PlatformToolset = v120 / v120_xp
WTL Include = C:\Dev\vc2013\WTL90_4140_Final\Include
```

したがって、Directory Nameだけを根拠にWTL 9.0.4140を最終Build Versionと断定しない。
`source.txt`はAuthorが明示したDevelopment Environmentであるため、PoC 1ではWTL 9.1 FinalをPrimary Candidateとする。

一方、Project Fileの固定PathはWTL 9.0.4140を示しているため、9.0.4140もCompatibility Profileとして保持し、必要に応じてA/B Buildできるようにする。

## 4. Pinned packages

Primary:

```text
WTL 9.1.5321 Final
SHA-256: c03f80c66f28e86b3cc7c98d14afab6bec8eb9366476f6bdda8469c35f52b18a
```

Compatibility profile:

```text
WTL 9.0.4140 Final
SHA-256: 3a4aa60e4c83d88a17b69852db22fbaf8caa4dccb083528d419c82801b686813
```

Version、Archive Name、SHA-256、取得先は`dependencies/wtl.json`で管理する。

## 5. Source policy

WTL Archive自体はRepositoryへCommitしない。

理由:

- Upstream配布物を不要に複製しない
- Third-party license / notice管理をRelease Artifactと分離する
- Repository sizeを増やさない
- 取得したBinary ArchiveのHash Verificationを明示する

RestoreはOfficial SourceForge配布物を使用し、SHA-256がManifestと一致した場合のみ展開する。

Downloadできない環境では、UserがOfficial Archiveを別途取得し、`-ArchivePath`で渡せる。

## 6. Local layout

Restore先:

```text
<Repository>\
└─ .deps\
   ├─ cache\
   │  └─ wtl\
   └─ wtl\
      ├─ 9.1.5321\
      │  └─ Include\
      └─ 9.0.4140\
         └─ Include\
```

`.deps\`はGenerated Dependency AreaでありGit管理しない。

Project側のDependency Propertyは`build/dependencies.props`へ集約する。
BM-003で`LhaForge.vcxproj`からこのProperty SheetをImportし、Machine固有Pathを除去した。

`build/dependencies.props`はWTL Include Directoryを`AdditionalIncludeDirectories`へ追加し、`atlapp.h`が存在しない場合はBuild開始前に明示的なErrorを出す。Build中にNetwork Restoreは実行しない。

## 7. Restore command

Default Primary Profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\restore-wtl.ps1
```

WTL 9.0.4140を比較用にRestore:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\restore-wtl.ps1 -Version 9.0.4140
```

Offline / manually downloaded archive:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\restore-wtl.ps1 -ArchivePath C:\Path\To\WTL91_5321_Final.zip
```

既存Restoreを置換:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\restore-wtl.ps1 -Force
```

## 8. Security requirements

Dependency Bootstrapは次を必須とする。

1. HTTPS経由で取得する。
2. Archiveを展開する前にSHA-256を検証する。
3. Hash不一致ArchiveをDependencyとして使用しない。
4. DownloadしたScript / Executableを自動実行しない。
5. Restore先をRepository配下の`.deps`へ限定する。
6. Administrator権限を要求しない。
7. Project Build時にNetwork Downloadを暗黙実行しない。

BuildそのものがDependency Downloadを行う設計にはしない。
Restoreは明示的なBootstrap Stepとする。

## 9. Reproducibility

同じRepository Revisionと同じ`dependencies/wtl.json`から、同一SHA-256のWTL PackageをRestoreできることをReproducible Buildの前提とする。

Network Sourceが将来消失した場合は、License確認後にProject-controlled Mirrorを追加できる設計とするが、Hashは変更しない。

Packageを変更する場合は、VersionとHashの変更を同一CommitでReviewする。

## 10. Verification

### 10.1 ATLとWTLのHeader境界

ATLとWTLのHeaderをDependency検証で混同しない。

Microsoft ATL側の代表的なHeader:

```text
atlbase.h
atlwin.h
```

WTL Archive側の代表的なHeader:

```text
atlapp.h
atlcrack.h
atlctrls.h
atlframe.h
atlmisc.h
atlres.h
```

`atlwin.h`はWTL Restore先の完全性判定には使用しない。ATL HeaderはVisual Studio / ATL Component側のEnvironment Verificationで確認する。

一方、`atlres.h`はWTL側のResource Headerとして扱い、WTL Restoreの完全性検証対象に含める。Resource Compilerにも`$(LhaForgeWTLInclude)`を渡す。

WTL Restoreは上記WTL固有HeaderがRestore先の`Include`に存在することを検証する。

### 10.2 Environment Gate

BM-002以降、`tools/verify-vs-environment.ps1`はVisual Studio / MSVC / SDK / ATLに加えてDefault WTL Profileも確認する。

Environment Gateは次が全て揃った場合にPassする。

```text
Visual Studio 2026
PlatformToolset v145
MSVC 14.44
ATL 14.44
Windows SDK 26100 family
WTL 9.1.5321 restored
```

## 11. WTL 10.x

WTL 10.xへの更新はBM-002に含めない。

PoC 1 / Regression Baseline成立後に、独立CommitでCompile、UI Behavior、DPI、Message Map等を比較する。

## 12. Planned Official Upstream / Built-in Backend / ZSTE dependencies

PoC 1ではWTLだけを実際にRestore / Pinしている。PoC 4以降のOfficial 7-ZipおよびZstandard / ZSTE実装時には、同じManifest / Hash Verification方針へRuntime Dependencyを追加する。


### Official 7-Zip

Design direction:

```text
7-Zip official upstream
Artifact: 7z.dll
Purpose:
  ZIP / 7z等を扱うManaged 7-Zip Backend
  LhaForgeからLibrary APIを直接利用
```

具体Version / SHA-256はPoC 4開始時にPinする。公式Upstream Libraryを優先し、`7z.exe`を標準Backendとして起動する設計にはしない。

`7-ZIP32.DLL`はこのManaged Dependencyへ置換して削除するのではなく、Integrated Archiver Compatibility / Legacy Optionとして別Ownershipで維持する。

### Zstandard

Candidate / design choice:

```text
facebook/zstd (libzstd)
License: BSD OR GPLv2 dual license
LhaForge usage direction: BSD terms
```

Zstd Format自体はstable public formatであり、`.zst` / `.tar.zst`の標準互換性を維持する。

Versionは実装開始時にPinし、Archive、SHA-256、License notice、Build flags、Multi-thread supportをManifestへ記録する。

`--max`相当機能はCLIに存在するAdvanced Parameter Presetであり、Library API上の「Level 23」として扱わない。Pinned Version更新時にPreset behaviorをReviewする。

### Argon2id implementation

Candidate / design choice:

```text
P-H-C/phc-winner-argon2 (official reference implementation)
License: CC0 OR Apache-2.0 dual license
Purpose:
  Argon2id v1.3 password-based key derivation
  explicit m / t / p parameter control
```

ZSTE v1はArgon2id v1.3をWire-levelで明示し、Memory Cost `m`、Time Cost `t`、Parallelism `p`をLibrary固有API名へ依存せず定義する。

libsodium high-level `crypto_pwhash(..., ALG_ARGON2ID13)`は現行実装で`p = 1`へ固定されるため、ZSTE v1のVendor-neutral KDF Parameterをその制約へ早期固定しない。Reference KDF LibraryはWire Freeze前のBenchmark / Security / License Reviewで最終選定する。

### libsodium

Candidate / design choice:

```text
jedisct1/libsodium
License: ISC
Purpose:
  XChaCha20-Poly1305 secretstream-compatible encryption/decryption
  secure random
  secure memory helpers
```

ZSTE Format Specificationそのものをlibsodium API名だけで定義しない。Secretstream-compatible Record LayerのExact RuleとTest Vectorを公開し、他Softwareがlibsodium利用または独立実装のどちらでも互換Reader / Writerを作れることを目標とする。

### Dependency gate

実際にSource / Binaryを取り込むCommitでは、最低限次を同時に行う。

1. Version pin
2. Official upstream source URL
3. SHA-256 pin
4. License / notice verification
5. x64 Windows build reproduction
6. Compiler mitigation確認
7. Upstream test suite / smoke test
8. Multi-thread / crypto feature availability check
9. Dependency update policy
10. SBOM / third-party noticeへの掲載方式

現段階ではVersionをRepository ManifestへPinしない。PoC 2-Bはv1.6.7 Regressionが目的であり、Built-in Zstd / ZSTE dependency導入は後段で行う。

---

## 13. Open items

- Primary WTL 9.1.5321とCompatibility WTL 9.0.4140のBuild差分
- Public Release時に必要なWTL License / Noticeの最終確認
- CIでDependency Cacheをどう扱うか
- Official Upstream / Built-in Backend dependencyをWTLと同じManifest思想へ統合する具体的なFile Layout
- Official 7-Zip `7z.dll`の初回Pinned Version / SHA-256 / License notice / Packaging layout
- libzstd / Argon2 implementation / libsodiumの初回Pinned VersionとSHA-256
- Static / dynamic link方針とRelease Notice
