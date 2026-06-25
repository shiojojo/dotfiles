#!/bin/sh
# ============================================================
# Dotfiles セットアップスクリプト (Harness Engineering)
# ============================================================
set -e

# --- 自身のディレクトリパスを確実に取得する ---
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔗 ハーネス設定のセットアップを開始します..."
echo "📂 検出された Dotfiles ディレクトリ: $DOTFILES_DIR"

# ---------------------------------------------------------
# 1. pnpm 設定の適用 (pnpm 11 の auth/非auth 分離対応)
# ---------------------------------------------------------
if command -v pnpm >/dev/null 2>&1; then
    # pnpm 11 の globalconfig は通常 rc (auth用) を指す
    PNPM_GLOBAL_RC="$(pnpm config get globalconfig 2>/dev/null || echo "$HOME/.config/pnpm/rc")"
    PNPM_CONFIG_DIR="$(dirname "$PNPM_GLOBAL_RC")"
    
    mkdir -p "$PNPM_CONFIG_DIR"
    
    # 1. auth用 (従来のINI形式: rc)
    if [ -f "$DOTFILES_DIR/pnpm/config" ]; then
        ln -snf "$DOTFILES_DIR/pnpm/config" "$PNPM_GLOBAL_RC"
        echo "✅ pnpm: rc (auth用/旧config) のリンクを作成しました ($PNPM_GLOBAL_RC)。"
    fi

    # 2. 非auth用 (pnpm 11 以降のYAML形式: config.yaml)
    PNPM_YAML="$PNPM_CONFIG_DIR/config.yaml"
    if [ -f "$DOTFILES_DIR/pnpm/config.yaml" ]; then
        ln -snf "$DOTFILES_DIR/pnpm/config.yaml" "$PNPM_YAML"
        echo "✅ pnpm: config.yaml のリンクを作成しました ($PNPM_YAML)。"
    fi
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
# 3. Git 設定の適用 (ローカル主導の Reverse Include 方式)
# ---------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "❌ git コマンドが見つかりません。Gitのインストールが必要です。"
    exit 1
fi

GITCONFIG_LOCAL="$HOME/.gitconfig"
GITCONFIG_SHARED="$DOTFILES_DIR/git/config_shared"

if [ -L "$GITCONFIG_LOCAL" ]; then
    echo "⚠️ ~/.gitconfig のシンボリックリンクを解除します..."
    rm "$GITCONFIG_LOCAL"
fi

if ! git config --global --get-all include.path 2>/dev/null | grep -qF "$GITCONFIG_SHARED"; then
    git config --global --add include.path "$GITCONFIG_SHARED"
    echo "✅ Git: ~/.gitconfig に共通設定 ($GITCONFIG_SHARED) の include を追加しました。"
else
    echo "✅ Git: ~/.gitconfig に共通設定の include は設定済みです。"
fi

ln -snf "$DOTFILES_DIR/git/gitignore_global" "$HOME/.gitignore_global"
echo "✅ Git: .gitignore_global のリンクを作成しました。"

# ---------------------------------------------------------
# 4. 実行スクリプトとシム (bin/) のセットアップ
# ---------------------------------------------------------
chmod +x "$DOTFILES_DIR/verify.sh"
echo "✅ verify.sh: 実行権限を付与しました。"

SHIM_DIR="$DOTFILES_DIR/bin"
chmod +x "$SHIM_DIR/harness-guard" "$SHIM_DIR/pnpm" "$SHIM_DIR/uv"

for cmd in npm npx pip pip3 uvx pnpx; do
    ln -snf harness-guard "$SHIM_DIR/$cmd"
done
echo "✅ bin/: シムのリンクを作成しました。"

# ---------------------------------------------------------
# 5. 監査ログ (Harness Guard) の環境準備
# ---------------------------------------------------------
HARNESS_LOG_DIR="$HOME/.local/state/harness/logs"
mkdir -p "$HARNESS_LOG_DIR"
touch "$HARNESS_LOG_DIR/blocked.log"
echo "✅ 監査ログ: $HARNESS_LOG_DIR/blocked.log を準備しました。"

# ---------------------------------------------------------
# 6. シェル環境設定の適用 (動的読み込み)
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

touch "$RC_FILE"

START_MARKER="# === BEGIN Dotfiles Harness Settings ==="
END_MARKER="# === END Dotfiles Harness Settings ==="

# 既存のBEGIN/ENDブロックがあれば安全に削除（ディレクトリ移動時の追従のため）
if grep -qF "$START_MARKER" "$RC_FILE"; then
    TMP_RC="$(mktemp)"
    sed "/^$START_MARKER$/,/^$END_MARKER$/d" "$RC_FILE" > "$TMP_RC"
    cat "$TMP_RC" > "$RC_FILE"
    rm -f "$TMP_RC"
    echo "🔄 OS($OS_TYPE): $RC_FILE の既存ハーネス設定を更新します..."
else
    echo "✅ OS($OS_TYPE): $RC_FILE に動的読み込み処理を追記します..."
fi

echo "" >> "$RC_FILE"
echo "$START_MARKER" >> "$RC_FILE"

# Dotfiles側のラッパー (bin/) を優先適用
echo "export PATH=\"$DOTFILES_DIR/bin:\$PATH\"" >> "$RC_FILE"

# 共通セキュリティルール (sec-*.sh) の一括読み込み
echo "for f in \"$DOTFILES_DIR\"/shell/sec-*.sh; do" >> "$RC_FILE"
echo "    [ -f \"\$f\" ] && source \"\$f\"" >> "$RC_FILE"
echo "done" >> "$RC_FILE"

# OS固有ルールの読み込み
echo "OS_FILE=\"$DOTFILES_DIR/shell/os-${OS_PREFIX}.sh\"" >> "$RC_FILE"
echo "[ -f \"\$OS_FILE\" ] && source \"\$OS_FILE\"" >> "$RC_FILE"

# ターミナル起動時の高速健全性チェック (--check)
echo "" >> "$RC_FILE"
echo "# ターミナル起動時の高速健全性チェック (--check)" >> "$RC_FILE"
echo "\"$DOTFILES_DIR/verify.sh\" --check 2>/dev/null || echo \"🚨 [Harness Guard] 環境の異常または改ざんを検知しました！ '$DOTFILES_DIR/verify.sh' で詳細を確認してください。\"" >> "$RC_FILE"

echo "$END_MARKER" >> "$RC_FILE"

echo "✅ OS($OS_TYPE): $RC_FILE に動的読み込み処理を追記しました。"

echo ""
echo "🎉 ハーネス設定のセットアップが完了しました！"
echo ""
echo "============================================================"
echo "📌 【重要】次にやるべきこと (Next Steps)"
echo "============================================================"
echo "1️⃣ シェルの設定を反映させるために、以下のコマンドを実行してください:"
echo "    source \"$RC_FILE\""
echo ""
echo "2️⃣ VS Code / Cursor のセキュリティ設定を手動で反映してください:"
echo "    1. 各エディタで「ユーザー設定 (JSON)」を開く"
echo "       VS Code: Cmd+Shift+P -> 'Open User Settings (JSON)'"
echo "       Cursor:  Cmd+Shift+P -> 'Preferences: Open User Settings (JSON)'"
echo "    2. 以下のファイルの内容をコピーし、ご自身の settings.json に追記する:"
echo "       $DOTFILES_DIR/vscode/settings.json"
echo ""
echo "3️⃣ すべての設定が正しく適用されたか、監査ツールで確認してください:"
echo "    ./verify.sh"
echo "============================================================"