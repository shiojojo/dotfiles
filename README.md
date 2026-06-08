# Dotfiles (Harness Engineering)

## 目的

- 生成AIが実行するスクリプトや依存解決を前提に、端末のデフォルトをセキュアにする。
- 個人情報を含む設定を分離し、共有設定は機械的に再現できる内容だけにする。
- **PATHレベルでのラッパー (Shim) を用いて、人間・AI問わず危険なコマンド実行を根本からブロックする。**

## 現在の構成

```text
dotfiles/
├── bin/                       ← AI・人間共通のコマンド実行ガード (Shim)
│   ├── harness-guard          (絶対ブロック共通スクリプト)
│   ├── pnpm, uv               (一部サブコマンドのみブロック＋パススルー)
│   └── npm, npx, pip, pip3, uvx, pnpx (harness-guardへのsymlink)
├── git/
│   ├── .gitconfig
│   └── .gitignore_global
├── pnpm/
│   └── config
├── vscode/
│   └── settings.json
├── shell/                     ← 環境変数・エイリアス定義
│   ├── sec-python.sh          (PIP_REQUIRE_VIRTUALENV等)
│   └── os-mac.sh              (macOS固有設定)
├── uv/
│   └── uv.toml
├── setup.sh
├── verify.sh
└── README.md
```

## 現在の適用内容

### pnpm

- hoist 無効化
- store integrity 検証
- exotic subdeps ブロック
- 新規公開パッケージ検疫 (7日)
- trust policy no-downgrade
- postinstall 全拒否
- **`npm` / `npx` / `pnpx` / `pnpm dlx` の直接実行を PATH ラッパーで完全ブロック**

### uv / Python

- 新規公開パッケージ検疫 (7日)
- index を PyPI 公式へ固定
- **`pip` / `pip3` / `uvx` / `uv tool run` の直接実行を PATH ラッパーで完全ブロック**
- `PIP_REQUIRE_VIRTUALENV=true` (グローバルへの pip インストール禁止)
- `UV_SYSTEM_PYTHON=false` (システム Python 書き換え禁止)

### Git (セキュリティ必須のみ)

- `core.excludesfile=~/.gitignore_global`
- `fetch.fsckObjects=true`
- `transfer.fsckObjects=true`
- `protocol.file.allow=never`
- `http.sslVerify=true`

### VS Code (時間差検疫)

- VS Code 設定は dotfiles で上書きしない
- `vscode/settings.json` は「コピペ用テンプレート」として管理する
- ユーザー設定に手動反映した内容を verify.sh で厳格監査する

### Homebrew / macOS (os-mac.sh)

- `HOMEBREW_NO_AUTO_UPDATE=1` (自動更新禁止)
- `HOMEBREW_CASK_OPTS=--require-sha` (SHA チェックサム必須)
- `HOMEBREW_NO_INSECURE_REDIRECT=1` (MITM 対策)
- `HOMEBREW_NO_ANALYTICS=1` (テレメトリ無効化)

## アップデート運用方針 (VS Code)

- 更新作業は週1回のメンテ枠でのみ実施する。
- 通知が出ても最低 3〜7 日は更新しない（時間差検疫）。
- 重大インシデント速報が出た拡張は更新せず、Marketplace の取り下げ確認後に再評価する。
- 例外的に即時更新した場合は、理由をこの README に記録する。

## setup.sh の現在動作

1. pnpm 設定をグローバル設定ファイルへリンク
2. uv 設定を `~/.config/uv/uv.toml` へリンク
3. Git 設定ファイルの存在確認とホームへのリンク作成
4. `bin/` 配下のシムスクリプト群への実行権限付与と、共通ガードへのシンボリックリンク生成
5. OS を自動判定し、RC ファイル (`.zshrc` / `.bashrc`) に以下を追記 (未設定時のみ)
   - **`export PATH="$DOTFILES_DIR/bin:$PATH"` (ガードの最優先適用)**
   - `sec-*.sh` を一括 source するループ (環境変数の適用)
   - `os-mac.sh` / `os-linux.sh` を OS に応じて source
   - `verify.sh --check` によるターミナル起動時の高速健全性チェック

## verify.sh の現在検証項目

`./verify.sh` はフル監査モードと高速チェックモードの2種類で動作する。

### フル監査モード (`./verify.sh`)

1. pnpm セキュリティ設定値
2. uv 設定リンクと設定値・PIP_REQUIRE_VIRTUALENV
3. Git リンク状態とセキュリティ必須値
4. VS Code の必須セキュリティ項目監査 (jq / grep フォールバック対応)
5. PATH ラッパー (`bin/`) が正しく最優先で適用されているかの監査
6. Homebrew セキュリティ設定値 (macOS のみ)
7. `bin/` の git 整合性チェック（改ざん・不審ファイルの検知）

### 高速健全性チェックモード (`./verify.sh --check`)

ターミナル起動時に自動実行される軽量チェック。外部コマンド呼び出しを最小化し数ミリ秒で完了する。

- PATH 先頭に `dotfiles/bin` があるか（case 文による厳格チェック）
- `PIP_REQUIRE_VIRTUALENV` が設定されているか
- `HOMEBREW_NO_AUTO_UPDATE` が設定されているか（macOS のみ）
- `.gitconfig` / `uv.toml` のシンボリックリンクが生きているか
- `bin/` のスクリプトが git 管理状態から改ざんされていないか

異常を検知した場合のみ警告を表示し、正常時は完全無音で終了する。

## verify.sh 実行前の注意

`setup.sh` 実行直後は環境変数がまだ反映されていないため、必ずシェルを再読み込みしてから実行すること。

```sh
source ~/.zshrc   # Mac
source ~/.bashrc  # Linux
./verify.sh
```

## VS Code の手動設定

1. VS Code で Settings(JSON) を開く
2. [vscode/settings.json](vscode/settings.json) の内容を必要項目として反映する
3. `./verify.sh` を実行し、VS Code 項目がすべて ✅ になることを確認する

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

## 今後追加すべきもの (提案)

1. 例外設定の明文化
   - プロジェクト側で検疫や build 制限を緩和する際、理由を README に記録する運用ルールを追加する。
2. Linux 固有設定の追加
   - `os-linux.sh` を作成し、Linux 環境固有のセキュリティ設定を追加する。
