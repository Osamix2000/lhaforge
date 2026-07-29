# LhaForge v1.7.0 Dependency Management

- Status: Draft
- Target: LhaForge v1.7.x
- Baseline: LhaForge v1.6.7
- Current scope: Build-time WTL dependency

## 1. Purpose

LhaForge v1.6.7のBuild定義にはDeveloper Machine固有のWTL Include Pathが残っている。
v1.7.xでは、Build Dependencyを特定PCの手作業配置に依存させず、Version、取得元、IntegrityをRepositoryから再現可能にする。

このDocumentはBM-002のDependency Restore方針を定義する。

## 2. Historical evidence and WTL version ambiguity

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

## 3. Pinned packages

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

## 4. Source policy

WTL Archive自体はRepositoryへCommitしない。

理由:

- Upstream配布物を不要に複製しない
- Third-party license / notice管理をRelease Artifactと分離する
- Repository sizeを増やさない
- 取得したBinary ArchiveのHash Verificationを明示する

RestoreはOfficial SourceForge配布物を使用し、SHA-256がManifestと一致した場合のみ展開する。

Downloadできない環境では、UserがOfficial Archiveを別途取得し、`-ArchivePath`で渡せる。

## 5. Local layout

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
BM-003でProjectをRetargetするとき、このProperty SheetをImportしてMachine固有Pathを除去する。

## 6. Restore command

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

## 7. Security requirements

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

## 8. Reproducibility

同じRepository Revisionと同じ`dependencies/wtl.json`から、同一SHA-256のWTL PackageをRestoreできることをReproducible Buildの前提とする。

Network Sourceが将来消失した場合は、License確認後にProject-controlled Mirrorを追加できる設計とするが、Hashは変更しない。

Packageを変更する場合は、VersionとHashの変更を同一CommitでReviewする。

## 9. Verification

### 9.1 ATLとWTLのHeader境界

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
```

`atlwin.h`はWTL Restore先の完全性判定には使用しない。ATL HeaderはVisual Studio / ATL Component側のEnvironment Verificationで確認する。

WTL Restoreは上記WTL固有HeaderがRestore先の`Include`に存在することを検証する。

### 9.2 Environment Gate

BM-002以降、`tools/verify-vs-environment.ps1`はVisual Studio / MSVC / SDK / ATLに加えてDefault WTL Profileも確認する。

Environment Gateは次が全て揃った場合にPassする。

```text
Visual Studio 2026
MSVC v143 / 14.44
ATL 14.44
Windows SDK 26100 family
WTL 9.1.5321 restored
```

## 10. WTL 10.x

WTL 10.xへの更新はBM-002に含めない。

PoC 1 / Regression Baseline成立後に、独立CommitでCompile、UI Behavior、DPI、Message Map等を比較する。

## 11. Open items

- Primary WTL 9.1.5321とCompatibility WTL 9.0.4140のBuild差分
- Public Release時に必要なWTL License / Noticeの最終確認
- CIでDependency Cacheをどう扱うか
- 将来のBuilt-in Backend dependencyを同じManifest方式へ統合するか
