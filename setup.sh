#!/bin/sh
# ============================================================
# Dotfiles セットアップスクリプト (Harness Engineering)
# ============================================================
set -e

# --- 修正点: 自身のディレクトリパスを確実に取得する ---
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔗 ハーネス設定のセットアップを開始します..."
echo "📂 検出された Dotfiles ディレクトリ: $DOTFILES_DIR"

# ---------------------------------------------------------
# 1. pnpm 設定の適用 (pnpm から動的にパスを取得)
# ---------------------------------------------------------
if command -v pnpm >/dev/null 2>&1; then
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
if [ ! -f "$DOTFILES_DIR/git/.gitconfig" ]; then
    echo "❌ $DOTFILES_DIR/git/.gitconfig が存在しません。"
    exit 1
fi

if [ ! -f "$DOTFILES_DIR/git/.gitignore_global" ]; then
    echo "❌ $DOTFILES_DIR/git/.gitignore_global が存在しません。"
    exit 1
fi

ln -snf "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
ln -snf "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
echo "✅ Git: .gitconfig と .gitignore_global のリンクを作成しました。"

# ---------------------------------------------------------
# 4. bin/ シムのセットアップ
# ---------------------------------------------------------
SHIM_DIR="$DOTFILES_DIR/bin"
chmod +x "$SHIM_DIR/harness-guard" "$SHIM_DIR/pnpm" "$SHIM_DIR/uv"

for cmd in npm npx pip pip3 uvx pnpx; do
    ln -snf harness-guard "$SHIM_DIR/$cmd"
done
echo "✅ bin/: シムのリンクを作成しました。"

# ---------------------------------------------------------
# 5. シェル環境設定の適用
# ---------------------------------------------------------
OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
    RC_FILE="$HOME/.zshrc"
    OS_PREFIX="mac"
elif [ "$OS_TYPE" = "Linux" ]; then
    RC_FILE="$HOME/.bashrc"
    OS_PREFIX="linux"
else
    echo "⚠️ サポートされていないOSです: $OS_TYPE"
    exit 1
fi

SOURCE_MARKER="# === Dotfiles Harness Settings ==="

touch "$RC_FILE"

if grep -qF "$SOURCE_MARKER" "$RC_FILE"; then
    echo "✅ OS($OS_TYPE): $RC_FILE には既にハーネス設定が存在します。"
else
    echo "" >> "$RC_FILE"
    echo "$SOURCE_MARKER" >> "$RC_FILE"
    
    # AIガード用 PATH ラッパー (bin/) を優先適用
    echo "export PATH=\"$DOTFILES_DIR/bin:\$PATH\"" >> "$RC_FILE"
    
    # 共通セキュリティルール (sec-*.sh) の一括読み込み
    echo "for f in \"$DOTFILES_DIR\"/shell/sec-*.sh; do" >> "$RC_FILE"
    echo "    [ -f \"\$f\" ] && source \"\$f\"" >> "$RC_FILE"
    echo "done" >> "$RC_FILE"
    
    # OS固有ルールの読み込み
    echo "OS_FILE=\"$DOTFILES_DIR/shell/os-${OS_PREFIX}.sh\"" >> "$RC_FILE"
    echo "[ -f \"\$OS_FILE\" ] && source \"\$OS_FILE\"" >> "$RC_FILE"
    
    echo "✅ OS($OS_TYPE): $RC_FILE に動的読み込み処理を追記しました。"
fi

echo ""
echo "🎉 すべてのセットアップが完了しました！"