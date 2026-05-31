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
│   └── security-python.zsh
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

### uv / Python

- 新規公開パッケージ検疫 (7日)
- index を PyPI 公式へ固定
- pip の直接利用抑止 (`PIP_REQUIRE_VIRTUALENV=true` + shell 関数)

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
5. `.zshrc` に shell 設定の読み込みを追記 (未設定時のみ)

## verify.sh の現在検証項目

1. pnpm セキュリティ設定値
2. uv 設定リンクと設定値
3. Git リンク状態とセキュリティ必須値
4. VS Code の必須セキュリティ9項目監査
5. `.zshrc` 読み込みマーカー

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
  "extensions.supportUntrustedWorkspaces": false,
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

2. shell のダウンロード実行ガード

- `curl ... | sh` のような直実行を避ける運用ルールを shell ファイルで明示する。

3. 監査ログの最小出力

- verify 結果を `./verify.sh --summary` で 1 行出力できるようにし、運用確認を簡素化する。

4. 例外設定の明文化

- プロジェクト側で検疫や build 制限を緩和する際、理由を README に記録する運用ルールを追加する。
