# Dotfiles — セキュア開発環境設定

## 目的

サプライチェーン攻撃・不正スクリプト実行・環境汚染を防ぐための、macOS / Linux 向けセキュリティ設定集。

- パッケージマネージャーの実行をデフォルトで制限し、意図しないコード実行を防ぐ。
- 個人情報を含む設定を分離し、共有設定は機械的に再現できる内容だけにする。
- **多層防御 (Defense in Depth):**
  1. **システム層 (OS環境変数):** バックグラウンドプロセスやGUIアプリを含むOS全体にグローバルな制限を強制する（root権限）。
  2. **ユーザー層 (PATHシム):** 危険なコマンド実行を物理的にインターセプトしてブロックする（通常権限）。

## 脅威モデル (Threat Model)

本設定が主に対象とする脅威：

- **サプライチェーン攻撃:** 悪意ある npm / PyPI パッケージによる postinstall スクリプト実行、タイポスクワッティング
- **時間差攻撃:** 公開直後の未検証パッケージのインストール
- **環境汚染:** システム Python / グローバル Node 環境への意図しない書き込み
- **AIエージェントのハルシネーション:** 生成AIが誤ったコマンドをバックグラウンドで実行しようとするケース

## 制限事項

ユーザー層防御（PATHシム）は**「ガードレール」**としての役割に特化しています。

- **絶対パス実行のすり抜け:** `/usr/local/bin/npm` などの絶対パスを用いた直接実行や、悪意のあるプロセスが意図的に PATH を書き換えた場合の実行までは防ぎません。
- **理由:** これらの行為が実行された時点でシステムはすでに侵害（Compromised）されている前提となり、PATHシムで防ぐべき脅威のスコープ外であるためです。過剰なインターセプトによる OS の破壊や脆弱性の誘発を避けるため、防御はシンプルなシェルスクリプトに留めています。

## 現在の構成

```text
dotfiles/
├── setup-system.sh            ← OS全体のセキュリティ設定 (root用)
├── verify-system.sh           ← OS環境変数の実効値監査 (root用)
├── setup.sh                   ← ユーザー環境・シムのセットアップ (一般ユーザー用)
├── verify.sh                  ← ユーザー環境・シムの監査 (一般ユーザー用)
├── bin/                       ← コマンド実行ガード (Shim)
│   ├── harness-guard          (絶対ブロック共通スクリプト)
│   ├── pnpm, uv               (一部サブコマンドのみブロック＋パススルー)
│   └── npm, npx, pip, pip3, uvx, pnpx (harness-guardへのsymlink)
├── pnpm/
│   ├── config                 (pnpm 11 auth用 INI設定)
│   └── config.yaml            (pnpm 11 非auth用 YAML設定)
├── shell/                     ← 環境変数・エイリアス定義
│   ├── sec-python.sh          (Python/uv セキュリティ環境変数: Mac/Linux共通)
│   ├── os-mac.sh              (macOS/zsh固有設定・履歴保護)
│   └── os-linux.sh            (Linux/bash固有設定・履歴保護)
├── uv/
│   └── uv.toml
├── git/
│   ├── config_shared
│   └── gitignore_global
├── vscode/
│   └── settings.json
└── README.md
```

## 現在の適用内容

### 1. システム全体防御 (System Layer: `/etc/zshenv` 等)

`setup-system.sh` によって全プロセスに以下の制約を強制する。

- **Node / npm / pnpm:**
  - `ignore-scripts=true` (Postinstall拒否)
  - `minimum-release-age=10080` (新規公開パッケージの7日検疫)
  - `PNPM_CONFIG_MINIMUM_RELEASE_AGE=10080` (pnpm v11 以降の仕様変更に対応)
- **Python / uv:**
  - `UV_EXCLUDE_NEWER=7 days` (7日検疫)
  - `UV_DEFAULT_INDEX` を PyPI 公式へ固定
  - `PIP_REQUIRE_VIRTUALENV=true` (システム汚染防止)

### 2. ユーザー・ツール防御 (User Layer: `bin/` Shim & Configs)

#### pnpm

- hoist 無効化 / shamefully-hoist 拒否
- store integrity 検証 / exotic subdeps ブロック
- trust policy no-downgrade (降格防止)
- **`npm` / `npx` / `pnpx` / `pnpm dlx` の直接実行を PATH ラッパーで完全ブロック**

#### uv / Python (`sec-python.sh`)

- `PIP_REQUIRE_VIRTUALENV=true` (グローバル Python 環境への直接インストール禁止)
- `UV_SYSTEM_PYTHON=false` (システム Python 書き換え禁止)
- **`pip` / `pip3` / `uvx` / `uv tool run` の直接実行を PATH ラッパーで完全ブロック**

#### Git (セキュリティ必須のみ)

- `core.excludesfile=~/.gitignore_global`
- `fetch.fsckObjects=true` / `transfer.fsckObjects=true`
- `protocol.file.allow=never`

#### VS Code / Cursor (時間差検疫と自動実行の遮断)

- 設定は上書きせず `vscode/settings.json` をコピペ用テンプレートとして管理し、両エディタに適用する。
- ユーザー設定に手動反映した内容を `verify.sh` で厳格監査する（自動更新の無効化など）。
- **注:** Cursor は AI 機能の利便性を優先し、初期状態で Workspace Trust が無効化されている
  （公式: "The Cursor IDE supports the standard workspace trust feature that is disabled by default."）。
  `settings.json` による明示的な有効化が必須。

#### Homebrew / macOS / zsh (`os-mac.sh`)

- `HOMEBREW_NO_AUTO_UPDATE=1` (自動更新禁止)
- `HOMEBREW_CASK_OPTS=--require-sha` (SHA チェックサム必須)
- `HOMEBREW_NO_INSECURE_REDIRECT=1` (MITM 対策) / テレメトリ無効化
- `HISTORY_IGNORE` (機密情報トークンの履歴除外)

#### apt / Linux / bash (`os-linux.sh`)

- `apt` 等はシステム全体に影響するため、`sudo` を伴う手動実行のみを正とし、ラッパー・自動化は行わない。
- `HISTCONTROL=ignoreboth` / `HISTIGNORE` (重複・機密トークンの履歴除外)

## セットアップ手順

セットアップは「システム層（root）」と「ユーザー層」の2段階で行う。

### 1. システム全体防衛設定 (Root)

OSのグローバル環境変数を安全に適用する。冪等性が担保されているため何度でも実行可能。

```sh
sudo ./setup-system.sh
# ※ 実行後、環境変数を読み込ませるためターミナルのタブを開き直すこと
```

### 2. ユーザー環境設定

Dotfilesのリンク作成とPATHシムの配置を行う。

```sh
./setup.sh
source ~/.zshrc   # Mac
# source ~/.bashrc  # Linux
```

## 監査 (Verify) 運用

### 1. システム環境監査 (Root)

システム環境変数（実効値）が OS に正しくロードされているかを検証する。

```sh
sudo ./verify-system.sh
```

### 2. フル監査モード (`./verify.sh`)

ユーザー権限での各種設定ファイルの実効値と、PATHシムの Git 整合性（改ざんチェック）をフル監査する。VS Code の設定手動反映後などに行う。

### 3. 高速健全性チェックモード (`./verify.sh --check`)

ターミナル起動時に `.zshrc` 等から自動実行されるミリ秒単位の軽量チェック。PATH の先頭が `dotfiles/bin` に向いているか、シムスクリプトに改ざん（未追跡ファイルの混入）がないかを監視し、異常時のみ警告を出す。

### 4. ブロック監査ログ

`harness-guard` によってブロックされたコマンドの履歴は、以下のログファイルに記録されます。不正なコマンド実行の事後確認に使用します。

- **ブロックログ:** `~/.local/state/harness/logs/blocked.log`

## VS Code / Cursor の手動設定手順

### 1. `settings.json` の適用（両エディタ共通）

1. 各エディタで Settings (JSON) を開く。
   - VS Code: `Cmd+Shift+P` → `Open User Settings (JSON)`
   - Cursor: `Cmd+Shift+P` → `Preferences: Open User Settings (JSON)`
2. `vscode/settings.json` の内容を自身の設定ファイルに追記する。
3. `./verify.sh` を実行し、すべて ✅ になることを確認する。

```json
{
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": true,
  "extensions.ignoreRecommendations": true,
  "security.workspace.trust.enabled": true,
  "security.workspace.trust.emptyWindow": false,
  "security.workspace.trust.untrustedFiles": "prompt",
  "security.workspace.trust.startupPrompt": "once",
  "task.allowAutomaticTasks": "off",
  "update.mode": "manual",
  "telemetry.telemetryLevel": "off",
  "workbench.enableExperiments": false,
  "npm.fetchOnlinePackageInfo": false,
  "git.autofetch": true
}
```

> **注:**
>
> - `workbench.enableExperiments: false` は Microsoft の A/B テスト配信を止める安定性設定であり、厳密にはセキュリティ設定ではない。
> - `task.allowAutomaticTasks: "off"` は Workspace Trust と組み合わせて機能する二重防御。単体では Workspace Trust の代替にならない。

### 2. Cursor 固有の GUI 設定（Cursor のみ・必須）

Cursor 固有の AI 通信・プライバシー設定は `settings.json` では制御できない仕様のため、
導入時に必ず以下を手動で設定する。

#### Privacy Mode の有効化

> 出典: Cursor 公式ドキュメント —
> "You can enable Privacy Mode at onboarding or under Cursor Settings > General > Privacy Mode."

1. 右上の歯車アイコン → `Cursor Settings` を開く。
2. `General` → `Privacy Mode` を **Enabled** にする。
3. 効果: コードが Cursor 社のサーバーに保存・学習データとして使用されるのを防ぐ。

#### Run Mode の設定（Agent コマンド実行の制御）

> 出典: Cursor 公式ドキュメント —
> "Configure how Cursor runs tools like command execution, MCP, and file writes
> at Settings > Cursor Settings > Agents > Run Mode."
>
> **公式の警告:** "Treat Auto-review as best-effort convenience, not a security boundary.
> For strict control, use Allowlist and approve calls yourself."

1. `Cursor Settings` → `Agents` → `Run Mode` を開く。
2. **`Allowlist`** を選択する。
   - デフォルトの `Auto-review` は公式が「セキュリティ境界ではない」と明言しているため不十分。
   - Allowlist に列挙されていないコマンドはすべて承認ダイアログが表示される。
3. 許可するコマンドを Allowlist に明示的に追加する（`git`、`pnpm` 等、プロジェクトに応じて判断）。

> **バージョン補足:** Cursor 3.5 以前の "Ask Every Time" は廃止済み。
> 代替は「Allowlist を空にして運用」する方法。
> 旧 "Run in Sandbox" は現在の "Allowlist (with Sandbox)" に相当する。

## アップデート運用方針 (VS Code / Cursor)

- 更新作業は週1回のメンテ枠でのみ実施する。
- 通知が出ても最低 3〜7 日は更新しない（時間差検疫）。
- 重大インシデント速報が出た拡張は更新せず、Marketplace の取り下げ確認後に再評価する。
- 例外的に即時更新した場合は、理由をこの README に記録する。
- 週次メンテ枠に各プロジェクトで `pnpm audit --prod` を実行し、既知の CVE を確認する。

## 例外運用ルール (Escape Hatches)

システム全体で強制しているセキュリティ制限を、明確な意図をもって一時的にバイパスする際の手順です。実行した場合は、必ずプロジェクトのコミットログや PR にその理由を記録してください。

### 1. 7日検疫のバイパス（緊急パッチ適用時など）

パッケージマネージャーのリリース日制限を一時的に無効化し、最新のパッケージをインストールします。

**Node.js (pnpm) の場合:**

環境変数で `MINIMUM_RELEASE_AGE` を 0 に上書きして実行します。

```sh
PNPM_CONFIG_MINIMUM_RELEASE_AGE=0 pnpm add <package-name>
```

**Python (uv) の場合:**

サブシェル内で `UV_EXCLUDE_NEWER` を明示的に解除して実行します。親シェルの環境変数は変更されません。

```sh
(unset UV_EXCLUDE_NEWER && uv add <package-name>)
```

### 2. インストールスクリプトの許可 (pnpm)

ネイティブバイナリのビルドなど、どうしても `postinstall` スクリプトの実行が必要な信頼できるパッケージに対してのみ、プロジェクトの `pnpm-workspace.yaml` に以下を追記して局所的に許可します（グローバルでは許可しない）。

```yaml
# pnpm-workspace.yaml (プロジェクトルート)
allowBuilds:
  <package-name>: true
```

> **注:** `onlyBuiltDependencies`（v10 以前）は pnpm v11 で廃止済み。
> `.npmrc` への記載も v11 では auth/registry 設定専用となり非 auth 設定は読まれない。
> 対話式に許可する場合は `pnpm approve-builds <package-name>` を実行すると
> `pnpm-workspace.yaml` に自動追記される。
>
> 出典: https://pnpm.io/settings#allowbuilds

### 3. `curl | sh` の実行（Homebrewインストール等）

PATHシムが防いでいない攻撃ベクタ。原則として禁止とし、以下の条件をすべて満たす場合のみ許可する。

1. 公式サイト・HTTPS であることをブラウザで直接確認する
2. スクリプトの内容を事前に目視確認する
   ```sh
   curl -fsSL <url> | less
   ```
3. 実行後に `./verify.sh` を走らせ、PATH・シムの健全性を確認する
4. 実行した事実とURLをコミットログに記録する

> Homebrew の初回インストールはこの例外に該当する代表的ケース。

## 検討・除外した設定 (Considered & Rejected)

導入を検討したが、スコープ外または費用対効果が低いと判断し、意図的に実装しなかった項目。

| 項目                                   | 除外理由                                                                                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GPG / SSH コミット署名                 | 個人プロジェクトでは費用対効果が低い。ローカル動作のAIエージェントは同一OSユーザーとして動作するため、署名でAI/人間のコミットを区別することも技術的に不可能。 |
| `~/.ssh/config` の `HashKnownHosts`    | `known_hosts` 漏洩は本設定の脅威モデルのスコープ外。                                                                                                          |
| Gatekeeper / SIP の状態検証            | SIP無効はシステムが侵害済みとみなすべき状態であり、shimレベルでの修復は不可能。検出のみで対処できないため除外。                                               |
| `setup-system.sh` へのバックアップ処理 | 冪等設計により再実行でリカバリー可能なため不要。                                                                                                              |
| `receive.fsckObjects=true` (Git)       | ローカルへの git bundle / patch 適用というシナリオが個人開発ではほぼ発生しない。                                                                              |
| `set -e` のスクリプト全体適用          | `grep` 等の終了コード1が意図せず処理を停止させるリスクがあり、全スクリプトへの適用コストが高い。冪等設計で代替する。※実装候補として保留中。                   |
