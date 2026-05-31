#!/bin/sh
# ============================================================
# Dotfiles セットアップスクリプト (Harness Engineering)
# ============================================================
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "🔗 ハーネス設定のセットアップを開始します..."
echo "📂 検出された Dotfiles ディレクトリ: $DOTFILES_DIR"

# ---------------------------------------------------------
# 1. pnpm 設定の適用 (pnpm から動的にパスを取得)
# ---------------------------------------------------------
if command -v pnpm >/dev/null 2>&1; then
    # pnpm が実際に使っている globalconfig のパスを特定
    PNPM_GLOBAL_RC="$(pnpm config get globalconfig)"
    PNPM_CONFIG_DIR="$(dirname "$PNPM_GLOBAL_RC")"
    
    mkdir -p "$PNPM_CONFIG_DIR"
    # 実体の config.yaml を、pnpm が期待するファイル(rc)としてリンクする
    ln -snf "$DOTFILES_DIR/pnpm/config.yaml" "$PNPM_GLOBAL_RC"
    echo "✅ pnpm: リンクを作成しました ($PNPM_GLOBAL_RC)。"
else
    echo "⚠️ pnpm コマンドが見つかりません。pnpmの設定をスキップします。"
fi

# ---------------------------------------------------------
# 2. Git 設定の適用 (シンボリックリンク)
# ---------------------------------------------------------
ln -snf "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
ln -snf "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
echo "✅ Git: .gitconfig と .gitignore_global のリンクを作成しました。"

# ---------------------------------------------------------
# 3. シェル環境 (zsh) 設定の適用 (source 読み込み)
# ---------------------------------------------------------
ZSHRC_FILE="$HOME/.zshrc"
SOURCE_CMD="source $DOTFILES_DIR/shell/harness.zsh"

touch "$ZSHRC_FILE"

if grep -qF "$SOURCE_CMD" "$ZSHRC_FILE"; then
    echo "✅ zsh: ~/.zshrc には既に harness.zsh の読み込み設定が存在します。"
else
    echo "" >> "$ZSHRC_FILE"
    echo "# === Dotfiles Harness Settings ===" >> "$ZSHRC_FILE"
    echo "$SOURCE_CMD" >> "$ZSHRC_FILE"
    echo "✅ zsh: ~/.zshrc に harness.zsh の読み込み設定を追記しました。"
fi

echo ""
echo "🎉 すべてのセットアップが完了しました！"