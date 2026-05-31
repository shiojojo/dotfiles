#!/bin/sh
# ============================================================
# Dotfiles 設定監査スクリプト (Harness Engineering)
#
# 目的: グローバルのセキュリティ設定が実際に有効かを検証する。
#       pnpm config list ではなく config get を使うことで、
#       フォーマット不正（YAML混入等）によるパース失敗も検出できる。
# ============================================================

PASS=0
FAIL=0

check() {
    local label="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(pnpm config get "$key" --global 2>/dev/null)"

    if [ "$actual" = "$expected" ]; then
        echo "  ✅ $label"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $label"
        echo "       期待値: '$expected'"
        echo "       実際値: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

echo "🔍 ハーネス設定の監査（ヘルスチェック）を開始します..."
echo "========================================================="

# ---------------------------------------------------------
# 1. pnpm セキュリティ設定
# ---------------------------------------------------------
echo "[1] pnpm セキュリティ設定"
if command -v pnpm >/dev/null 2>&1; then
    check "hoist=false (ファントム依存防止)"          hoist                    "false"
    check "shamefully-hoist=false"                    shamefully-hoist         "false"
    check "verify-store-integrity=true (改ざん検知)"  verify-store-integrity   "true"
    check "block-exotic-subdeps=true (裏口DL遮断)"    block-exotic-subdeps     "true"
    check "minimum-release-age=10080 (7日検疫)"       minimum-release-age      "10080"
    check "minimum-release-age-strict=true"           minimum-release-age-strict "true"
    check "trust-policy=no-downgrade (降格防止)"      trust-policy             "no-downgrade"
    check "allow-builds='' (postinstall全拒否)"        allow-builds             ""
else
    echo "  ⚠️ pnpm がインストールされていないか、パスが通っていません。"
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 2. uv セキュリティ設定
# ---------------------------------------------------------
echo "[2] uv セキュリティ設定"
if command -v uv >/dev/null 2>&1; then
    UV_TOML="$HOME/.config/uv/uv.toml"

    # uv には config get コマンドがないため toml ファイルを直接パースする
    uv_get() {
        grep "^$1" "$UV_TOML" 2>/dev/null | sed 's/.*= *//' | tr -d '"'
    }

    uv_check() {
        local label="$1"
        local key="$2"
        local expected="$3"
        local actual
        actual="$(uv_get "$key")"
        if [ "$actual" = "$expected" ]; then
            echo "  ✅ $label"
            PASS=$((PASS + 1))
        else
            echo "  ❌ $label"
            echo "       期待値: '$expected'"
            echo "       実際値: '$actual'"
            FAIL=$((FAIL + 1))
        fi
    }

    # 設定ファイルがシンボリックリンクかチェック
    if [ -L "$UV_TOML" ]; then
        echo "  ✅ uv.toml はシンボリックリンクです ($(readlink "$UV_TOML"))"
        PASS=$((PASS + 1))
    else
        echo "  ❌ uv.toml がシンボリックリンクではありません（dotfiles 管理外）"
        FAIL=$((FAIL + 1))
    fi

    uv_check "exclude-newer=\"7 days\" (7日検疫)"  exclude-newer  "7 days"
    uv_check "index url = pypi.org (公式レジストリ固定)" url "https://pypi.org/simple"

    # pip 禁止チェック（PIP_REQUIRE_VIRTUALENV が設定されているか）
    if [ "$PIP_REQUIRE_VIRTUALENV" = "true" ]; then
        echo "  ✅ PIP_REQUIRE_VIRTUALENV=true (仮想環境外インストール禁止)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ PIP_REQUIRE_VIRTUALENV が設定されていません"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ⚠️ uv がインストールされていないか、パスが通っていません。"
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 3. Git の設定チェック
# ---------------------------------------------------------
echo "[3] Git グローバル設定"
if command -v git >/dev/null 2>&1; then
    EXCLUDES=$(git config --global core.excludesfile || echo "")
    if echo "$EXCLUDES" | grep -q ".gitignore_global"; then
        echo "  ✅ core.excludesfile ($EXCLUDES)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ core.excludesfile (.gitignore_global が設定されていません)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ⚠️ Git がインストールされていません。"
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 4. Zsh 設定チェック
# ---------------------------------------------------------
echo "[4] シェル環境"
ZSHRC_FILE="$HOME/.zshrc"
if [ -f "$ZSHRC_FILE" ] && grep -qF "# === Dotfiles Harness Settings ===" "$ZSHRC_FILE"; then
    echo "  ✅ ~/.zshrc にハーネス設定の読み込みが存在します"
    PASS=$((PASS + 1))
else
    echo "  ❌ ~/.zshrc からハーネス設定が読み込まれていません"
    FAIL=$((FAIL + 1))
fi
echo "========================================================="
echo "結果: ✅ $PASS 件成功 / ❌ $FAIL 件失敗"

[ "$FAIL" -eq 0 ]