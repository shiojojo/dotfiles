# Dotfiles (Harness Engineering)

## 目的

- 生成AIが実行するスクリプトや依存解決を前提に、端末のデフォルトをセキュアにする。
- 個人情報を含む設定を分離し、共有設定は機械的に再現できる内容だけにする。

## 現在の構成

```
dotfiles/
├── git/
│   ├── .gitconfig
│   └── .gitignore_global
├── pnpm/
│   └── config
├── vscode/
│   └── settings.json
├── shell/
│   ├── sec-python.sh
│   ├── sec-node.sh
│   └── os-mac.sh
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
- `npm` / `npx` / `pnpx` / `pnpm dlx` の直接実行ブロック

### uv / Python

- 新規公開パッケージ検疫 (7日)
- index を PyPI 公式へ固定
- `pip` / `pip3` の全面無効化 (`PIP_REQUIRE_VIRTUALENV=true` + shell 関数)
- `uvx` / `uv tool run` の直接実行ブロック
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
3. Git 設定ファイルの存在確認
4. `.gitconfig` と `.gitignore_global` をホームへリンク
5. OS を自動判定し、RC ファイル (`.zshrc` / `.bashrc`) に以下を追記 (未設定時のみ)
   - `sec-*.sh` を一括 source するループ
   - `os-mac.sh` / `os-linux.sh` を OS に応じて source

## verify.sh の現在検証項目

1. pnpm セキュリティ設定値
2. uv 設定リンクと設定値・PIP_REQUIRE_VIRTUALENV
3. Git リンク状態とセキュリティ必須値
4. VS Code の必須セキュリティ項目監査 (jq / grep フォールバック対応)
5. シェル環境の読み込みマーカー (OS 判定対応)
6. Homebrew セキュリティ設定値 (macOS のみ)

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

## 無駄な処理の確認結果

- setup.sh / verify.sh に、現在の基本方針と矛盾する処理はなし。
- 過去の拡張でできた空ディレクトリ (`git/hooks`, `.github/workflows`) は削除済み。

## 今後追加すべきもの (提案)

1. verify の「必須/任意」モード分離
   - `./verify.sh --strict` を追加し、CI とローカル確認で厳しさを切り替える。

2. 監査ログの最小出力
   - verify 結果を `./verify.sh --summary` で 1 行出力できるようにし、運用確認を簡素化する。

3. 例外設定の明文化
   - プロジェクト側で検疫や build 制限を緩和する際、理由を README に記録する運用ルールを追加する。

4. Linux 固有設定の追加
   - `os-linux.sh` を作成し、Linux 環境固有のセキュリティ設定を追加する。
