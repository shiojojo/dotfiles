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
    ln -snf "$DOTFILES_DIR/pnpm/config" "$PNPM_GLOBAL_RC"
    echo "✅ pnpm: リンクを作成しました ($PNPM_GLOBAL_RC)。"
else
    echo "⚠️ pnpm コマンドが見つかりません。pnpmの設定をスキップします。"
fi

# ---------------------------------------------------------
# 2. uv 設定の適用
# ---------------------------------------------------------
if command -v uv >/dev/null 2>&1; then
    UV_CONFIG_DIR="$HOME/.config/uv"
    mkdir -p "$UV_CONFIG_DIR"
    ln -snf "$DOTFILES_DIR/uv/uv.toml" "$UV_CONFIG_DIR/uv.toml"
    echo "✅ uv: リンクを作成しました ($UV_CONFIG_DIR/uv.toml)。"
else
    echo "⚠️ uv コマンドが見つかりません。uvの設定をスキップします。"
fi

# ---------------------------------------------------------
# 3. Git 設定の適用 (シンボリックリンク)
# ---------------------------------------------------------
ln -snf "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
ln -snf "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
echo "✅ Git: .gitconfig と .gitignore_global のリンクを作成しました。"

# ---------------------------------------------------------
# 4. シェル環境 (zsh) 設定の適用
# ---------------------------------------------------------
ZSHRC_FILE="$HOME/.zshrc"
SOURCE_MARKER="# === Dotfiles Harness Settings ==="
SOURCE_CMD="for f in $DOTFILES_DIR/shell/*.zsh; do source \"\$f\"; done"

touch "$ZSHRC_FILE"

if grep -qF "$SOURCE_MARKER" "$ZSHRC_FILE"; then
    echo "✅ zsh: ~/.zshrc には既にハーネス設定の読み込みが存在します。"
else
    echo ""               >> "$ZSHRC_FILE"
    echo "$SOURCE_MARKER" >> "$ZSHRC_FILE"
    echo "$SOURCE_CMD"    >> "$ZSHRC_FILE"
    echo "✅ zsh: ~/.zshrc にハーネス設定の読み込みを追記しました。"
fi

echo ""
echo "🎉 すべてのセットアップが完了しました！"