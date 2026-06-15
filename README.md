# Dotfiles (Harness Engineering)

## 目的

- 生成AIが実行するスクリプトや依存解決を前提に、端末のデフォルトをセキュアにする。
- 個人情報を含む設定を分離し、共有設定は機械的に再現できる内容だけにする。
- **多層防御 (Defense in Depth):**
  1. **システム層 (OS環境変数):** バックグラウンドプロセスやGUIアプリを含むOS全体にグローバルな制限を強制する（root権限）。
  2. **ユーザー層 (PATHシム):** 人間・AI問わず、引数による強制突破などの危険なコマンド実行を物理的にインターセプトしてブロックする（通常権限）。

## 現在の構成

```text
dotfiles/
├── setup-system.sh            ← OS全体のセキュリティ設定 (root用)
├── verify-system.sh           ← OS環境変数の実効値監査 (root用)
├── setup.sh                   ← ユーザー環境・シムのセットアップ (一般ユーザー用)
├── verify.sh                  ← ユーザー環境・シムの監査 (一般ユーザー用)
├── bin/                       ← AI・人間共通のコマンド実行ガード (Shim)
│   ├── harness-guard          (絶対ブロック共通スクリプト)
│   ├── pnpm, uv               (一部サブコマンドのみブロック＋パススルー)
│   └── npm, npx, pip, pip3, uvx, pnpx (harness-guardへのsymlink)
├── pnpm/
│   ├── config                 (pnpm 11 auth用 INI設定)
│   └── config.yaml            (pnpm 11 非auth用 YAML設定)
├── shell/                     ← 環境変数・エイリアス定義
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

#### uv / Python

- `UV_SYSTEM_PYTHON=false` (システム Python 書き換え禁止)
- **`pip` / `pip3` / `uvx` / `uv tool run` の直接実行を PATH ラッパーで完全ブロック**

#### Git (セキュリティ必須のみ)

- `core.excludesfile=~/.gitignore_global`
- `fetch.fsckObjects=true` / `transfer.fsckObjects=true`
- `protocol.file.allow=never`
- `http.sslVerify=true`

#### VS Code (時間差検疫)

- VS Code 設定は上書きせず `vscode/settings.json` をコピペ用テンプレートとして管理。
- ユーザー設定に手動反映した内容を `verify.sh` で厳格監査する（自動更新の無効化など）。

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

## VS Code の手動設定手順

1. VS Code で Settings(JSON) を開く (Mac: `Cmd+Shift+P` -> `Open User Settings (JSON)`)
2. 以下の内容をご自身の `settings.json` に追記する。
3. `./verify.sh` を実行し、すべて ✅ になることを確認する。

```json
{
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": true,
  "security.workspace.trust.enabled": true,
  "security.workspace.trust.emptyWindow": false,
  "security.workspace.trust.untrustedFiles": "prompt",
  "update.mode": "manual",
  "telemetry.telemetryLevel": "off",
  "workbench.enableExperiments": false
}
```

## アップデート運用方針 (VS Code)

- 更新作業は週1回のメンテ枠でのみ実施する。
- 通知が出ても最低 3〜7 日は更新しない（時間差検疫）。
- 重大インシデント速報が出た拡張は更新せず、Marketplace の取り下げ確認後に再評価する。
- 例外的に即時更新した場合は、理由をこの README に記録する。

## 今後追加すべきもの (提案)

1. 例外設定の明文化
   - プロジェクト側で検疫や build 制限を緩和する際（例: pnpm の `allow-builds` の許可など）、理由を README に記録する運用ルールを追加する。
