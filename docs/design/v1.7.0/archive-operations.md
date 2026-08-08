# LhaForge v1.7.0 Archive Operation Design

* Status: Draft
* Target: LhaForge v1.7.x
* Purpose: Backend種別に依存しない圧縮・展開操作の共通Policyを定義する。

## 1. Principle

圧縮対象の列挙、除外Policy、展開先決定等のUser-facingな操作Policyは、External DLLやBuilt-in Backendの個別実装へ直接持たせない。

ArchiveManagerの上位に共通のOperation Planning Layerを設ける。

```text
User Operation
      ↓
Operation Planner
      ├─ Input Enumeration
      ├─ Exclusion Policy
      ├─ Destination Policy
      ├─ Security Validation
      └─ Operation Plan
              ↓
        ArchiveManager
              ↓
        Selected Backend
```

これによりZIP、7z、TAR、Legacy DLL等のBackend種別に関係なく、同じ設定・Security Policyを適用する。

## 2. Compression Input Plan

圧縮時は、Backendへ元Directoryをそのまま渡す前に、LhaForge側で対象File Setを確定できる設計とする。

```text
Selected Files / Directories
        ↓
Enumerate once
        ↓
Normalize relative paths
        ↓
Apply exclusion rules
        ↓
Security / accessibility checks
        ↓
Final Input Set
        ↓
Backend
```

可能な限りFilesystem走査を1回に集約し、除外判定のために同じDirectory Treeを繰り返しScanしない。

## 3. Sensitive / Unwanted File Exclusion

圧縮時に、共有したくないMetadataや秘密情報をArchiveへ誤って含めることを減らす機能を提供する。

主な例:

* `.git` Directory / File
* `.env`
* `.env.*`
* `.svn`
* `.hg`

ただし、特定File名だけで秘密情報を完全に検出できるとはみなさない。

この機能は誤共有防止の補助機能であり、Secret Scannerそのものではない。

## 4. Exclusion Mode

ユーザーは少なくとも次のModeを選択できるようにする。

### Do not exclude

除外Listを適用せず、選択された対象を通常どおり圧縮する。

### Exclude automatically

有効になっている除外Ruleに一致するFile / Directoryを自動的にArchive対象から除外する。

### Ask when compressing

圧縮開始前に一致項目を検出し、今回のArchiveで除外するかユーザーが確認できる。

設定名やUI文言は実装時に調整するが、Policyとしてこの3種類を維持する。

## 5. Exclusion Rule List

Option画面で除外Ruleを追加・削除・有効化・無効化できるようにする。

Ruleには少なくとも次の情報を持てる構造を想定する。

```text
Pattern
Enabled
Target: File / Directory / Both
Scope: Any depth / Root only
Description (optional)
```

初期Ruleは保守的に設定し、一般的なProject Fileを過剰に除外しない。

初期候補:

```text
.git        Directory or .git metadata file
.svn       Directory
.hg        Directory
.env        File
.env.*      File pattern
```

`.gitignore`は`.git`とは別物なので、`.git` Ruleだけで自動除外しない。

`.env.example`等の共有目的Fileについては、例外Ruleまたは個別確認を可能にする。

Private Key、Credential、Cloud設定等の追加Presetを将来提供できるが、誤検出・正当な共有用途を考慮して初期状態で無条件除外するかは別途決定する。

## 6. Rule Syntax

Rule Syntaxは実装前に最終決定する。

候補はGitignore風Wildcardを参考にするが、`.gitignore`ファイルそのものを自動読込してArchive除外へ流用することは別機能として扱う。

最低限必要な表現:

* Exact file name
* Exact directory name
* Wildcard extension / suffix
* Relative path pattern
* Root-only / recursive match
* Exception / Allow rule

Windows上では通常Case-insensitive Matchingを基本とするが、Archive内部名や他Platform由来Fileとの扱いはEncoding / Compatibility設計と合わせて決定する。

## 7. Security Requirement for Backend Adapters

除外Ruleが有効な場合、Backendが独自にDirectoryを再列挙して除外済みFileを追加してしまってはならない。

したがってBackend Capabilityとして、最終Input Setを正確に処理できるかを管理する。

例:

```text
Create
ExactInputSet
InputList
ExcludePattern
```

Operation Plannerが除外した対象をBackendへ渡さないことを保証できないBackendでは、Filtered Createを利用不可と判定する。

安全性のため、除外有効時に「とりあえず親DirectoryをBackendへ渡す」Fallbackは行わない。

必要であれば別Backendを選択するか、操作不能として明確に通知する。

大量Fileを一時DirectoryへCopyしてから圧縮する方式はI/Oと容量を大幅に増やすため、原則的な実装にはしない。

## 8. Compression Preview

`Ask when compressing`では、圧縮開始前に最低限次を確認できるようにする。

* 除外されるFile / Directory数
* 除外理由 / Rule
* 今回だけ含める・除外する選択
* 必要なら詳細一覧

大量項目ではUIへ全Fileを逐次追加してPerformanceを悪化させないよう、集計と遅延表示を利用する。

## 9. Extraction Destination by Archive Name

展開時に、Archive File名を元にDirectoryを作成し、その中へ展開するOptionを提供する。

例:

```text
sample.zip
    ↓
sample\

backup.7z
    ↓
backup\

source.tar.gz
    ↓
source\
```

このPolicyはZIPだけではなく、認識可能なArchive形式全体で利用可能にする。

## 10. Archive Base Name Resolution

単純に最後の拡張子1つだけを削除せず、Format Registryが認識する最長のArchive suffixを利用してLogical Base Nameを求める。

例:

```text
source.tar.gz   → source
source.tgz      → source
backup.tar.xz   → backup
package.tar.zst → package
```

Multi-volume Archiveは、BackendまたはFormat Registryが認識したArchive SetのLogical Nameを優先する。

例として`backup.part1.rar`等を単純な文字列処理だけで決定しない。

## 11. Extraction Destination Modes

少なくとも次の選択を許容する。

* 指定Directoryへ直接展開
* Archive名のSubdirectoryを作成して展開
* 圧縮Fileと同じ場所にArchive名Directoryを作成

既存v1系設定とのCompatibilityを確認し、既存Modeを削除せず追加選択肢として設計する。

## 12. Destination Name Safety

Archive名からDirectoryを作る際も、File名を無条件に信用しない。

次を考慮する。

* Windowsで使用できない文字
* Reserved Device Name
* Trailing Dot / Space
* 空文字
* `.` / `..`
* 異常に長いName
* Unicode Control Character
* Existing File / Directory Collision

Collision時のPolicyは設定可能または明示的に決定する。

候補:

```text
sample\
sample (2)\
sample (3)\
```

既存Directoryへ自動MergeするかどうかはOverwrite Policyと合わせて別途定義する。

## 13. Security and Performance Principles

Archive操作の内部設計では、署名の有無に関係なくSecurityとPerformanceを基本要件とする。

### Security

* Input / Output Path Validation
* Path Traversal対策
* Symlink / Junction / Reparse Pointの扱い
* DLL Load Security
* Secret / Unwanted Fileの誤Archive防止
* Backendへ渡すInput Setの一貫性
* Failure時のPartial Output管理
* Archive Bomb / Resource Exhaustion対策

### Performance

* Directory Treeの不要な再Scanを避ける
* 大量File一覧を不必要にMemoryへ複製しない
* BackendへArchive DataをIPC転送しない
* 除外機能のためのFull staging copyを原則行わない
* UI更新をBatch / Throttleする
* Backendごとの性能特性をCapability / Policyに反映できる構造とする

Securityのために必要なValidationは省略しないが、同じ情報を複数Layerで無意味に再計算しない。

## 14. Logging

圧縮時には、必要に応じて次をDebug / Traceへ記録する。

* Input count
* Excluded count
* Exclusion Rule summary
* Backend selection
* Final input plan generation result

Secret Fileの内容はLogへ出力しない。

File名自体も機密になり得るため、通常Levelで大量のFull Pathを出力しない。

## 15. Zstandard / ZSTE Compression Profiles

Zstandard Compressionは`.zst`と`.zste`で同じProfile Modelを利用する。

DefaultではProfileを共有する。

```text
.zst / .tar.zst
       ↑
  shared profile
       ↓
.zste / .tar.zste
```

Default Profile:

```text
Compression level: 22 (Ultra)
Thread policy: Auto / Performance
Maximum compression (--max equivalent): OFF
```

`Auto / Performance`は最大Thread数を無条件に使用するPolicyではない。

> Compression Level 22を維持した上で、利用可能Hardwareを使って実際の処理時間を短縮する

ことを目的とする。

Zstd CLIの`--max`はLevel 23ではなくAdvanced Parameter Presetである。Advanced Optionとして明示的に選択可能にするがDefaultでは無効とし、UIには大量のMemoryと長い処理時間を使用し得ること、および生成Frameによっては展開側にも大きなMemory / Window Limitが必要になる旨の注意書きを表示する。確認Dialogは必須としない。

UserがProfile共有を解除した場合、`.zst`系と`.zste`系でLevel / Thread Policy / Maximum Compression等を独立設定できる。

`.zste`は単一Data Stream、`.tar.zste`はTAR StreamをZstd圧縮してからAuthenticated Encryptionする。

```text
Single file:
  input -> Zstd -> ZSTE encryption -> .zste

Multiple files / directory:
  input set -> TAR -> Zstd -> ZSTE encryption -> .tar.zste
```

DecodeにCompression LevelやThread数は不要であるため、これらはCreate-side ProfileでありZSTE必須Header Metadataとはしない。

ZSTEのWire Format、KDF、Authentication、Output Commit Policyは`zste-format.md`およびADR-0006に従う。

---

## 16. Open Items

* Rule Syntaxの最終仕様
* Default Rule Set
* `.env.example`等の初期Exception
* `.gitignore` Rule Import機能の要否
* Exclusion Preview UI
* Backend別`ExactInputSet`対応状況
* Extraction collision policy
* Multi-volume Logical NameのBackend共通表現
