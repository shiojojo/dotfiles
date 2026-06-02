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

git_check() {
    local label="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(git config --global --get "$key" 2>/dev/null || echo "")"

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

    # awk を用いた堅牢なパース (スペース/クォート揺れに対応)
    uv_get() {
        local target_key="$1"
        awk -F'=' -v key="$target_key" '
            {
                k=$1; gsub(/^[ \t]+|[ \t]+$/, "", k)
                if (k == key) {
                    v=$2; 
                    gsub(/^[ \t]+|[ \t]+$/, "", v); 
                    gsub(/["'"'"']/, "", v); 
                    print v
                }
            }
        ' "$UV_TOML"
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

    uv_check "exclude-newer (7日検疫)"  exclude-newer  "7 days"
    uv_check "url (公式レジストリ固定)"  url             "https://pypi.org/simple"

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
    if [ -L "$HOME/.gitconfig" ]; then
        echo "  ✅ ~/.gitconfig はシンボリックリンクです ($(readlink "$HOME/.gitconfig"))"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ~/.gitconfig がシンボリックリンクではありません"
        FAIL=$((FAIL + 1))
    fi

    if [ -L "$HOME/.gitignore_global" ]; then
        echo "  ✅ ~/.gitignore_global はシンボリックリンクです ($(readlink "$HOME/.gitignore_global"))"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ~/.gitignore_global がシンボリックリンクではありません"
        FAIL=$((FAIL + 1))
    fi

    EXCLUDES="$(git config --global --get core.excludesfile || echo "")"
    if [ "$EXCLUDES" = "$HOME/.gitignore_global" ] || [ "$EXCLUDES" = "~/.gitignore_global" ]; then
        echo "  ✅ core.excludesfile ($EXCLUDES)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ core.excludesfile (~/.gitignore_global が設定されていません)"
        FAIL=$((FAIL + 1))
    fi

    # Security-critical Git checks
    git_check "fetch.fsckObjects=true"         fetch.fsckObjects      "true"
    git_check "transfer.fsckObjects=true"      transfer.fsckObjects   "true"
    git_check "protocol.file.allow=never"      protocol.file.allow    "never"
    git_check "http.sslVerify=true"            http.sslVerify         "true"
else
    echo "  ⚠️ Git がインストールされていません。"
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 4. VS Code セキュリティ設定
# ---------------------------------------------------------
echo "[4] VS Code 環境"
case "$(uname -s)" in
  Darwin) VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json" ;;
  Linux)  VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json" ;;
  *)      VSCODE_SETTINGS="" ;;
esac

if [ -f "$VSCODE_SETTINGS" ]; then
    VSCODE_JSON_VALID=0
    if command -v jq >/dev/null 2>&1 && jq empty "$VSCODE_SETTINGS" >/dev/null 2>&1; then
        VSCODE_JSON_VALID=1
    fi

    vsc_check_bool() {
        local label="$1"
        local key="$2"
        local expected="$3"
        local regex="$4"
        local actual

        if [ "$VSCODE_JSON_VALID" -eq 1 ]; then
            actual="$(jq -r ".[\"$key\"] // \"未設定\"" "$VSCODE_SETTINGS" 2>/dev/null || echo "未設定")"
            if [ "$actual" = "$expected" ]; then
                echo "  ✅ $label"
                PASS=$((PASS + 1))
            else
                echo "  ❌ $label"
                echo "       期待値: '$expected'"
                echo "       実際値: '$actual'"
                FAIL=$((FAIL + 1))
            fi
        else
            if grep -Eq "$regex" "$VSCODE_SETTINGS"; then
                echo "  ✅ $label"
                PASS=$((PASS + 1))
            else
                echo "  ❌ $label"
                FAIL=$((FAIL + 1))
            fi
        fi
    }

    vsc_check_string() {
        local label="$1"
        local key="$2"
        local expected="$3"
        local regex="$4"
        local actual

        if [ "$VSCODE_JSON_VALID" -eq 1 ]; then
            actual="$(jq -r ".[\"$key\"] // \"未設定\"" "$VSCODE_SETTINGS" 2>/dev/null || echo "未設定")"
            if [ "$actual" = "$expected" ]; then
                echo "  ✅ $label"
                PASS=$((PASS + 1))
            else
                echo "  ❌ $label"
                echo "       期待値: '$expected'"
                echo "       実際値: '$actual'"
                FAIL=$((FAIL + 1))
            fi
        else
            if grep -Eq "$regex" "$VSCODE_SETTINGS"; then
                echo "  ✅ $label"
                PASS=$((PASS + 1))
            else
                echo "  ❌ $label"
                FAIL=$((FAIL + 1))
            fi
        fi
    }

    vsc_check_bool "extensions.autoUpdate=false (時間差検疫の土台)" "extensions.autoUpdate" "false" '"extensions\.autoUpdate"[[:space:]]*:[[:space:]]*false'
    vsc_check_bool "extensions.autoCheckUpdates=true (通知のみ許可)" "extensions.autoCheckUpdates" "true" '"extensions\.autoCheckUpdates"[[:space:]]*:[[:space:]]*true'
    vsc_check_bool "security.workspace.trust.enabled=true" "security.workspace.trust.enabled" "true" '"security\.workspace\.trust\.enabled"[[:space:]]*:[[:space:]]*true'
    vsc_check_bool "security.workspace.trust.emptyWindow=false" "security.workspace.trust.emptyWindow" "false" '"security\.workspace\.trust\.emptyWindow"[[:space:]]*:[[:space:]]*false'
    vsc_check_string "security.workspace.trust.untrustedFiles=prompt" "security.workspace.trust.untrustedFiles" "prompt" '"security\.workspace\.trust\.untrustedFiles"[[:space:]]*:[[:space:]]*"prompt"'
    vsc_check_string "update.mode=manual" "update.mode" "manual" '"update\.mode"[[:space:]]*:[[:space:]]*"manual"'
    vsc_check_string "telemetry.telemetryLevel=off" "telemetry.telemetryLevel" "off" '"telemetry\.telemetryLevel"[[:space:]]*:[[:space:]]*"off"'
    vsc_check_bool "workbench.enableExperiments=false" "workbench.enableExperiments" "false" '"workbench\.enableExperiments"[[:space:]]*:[[:space:]]*false'
else
    echo "  ❌ VS Code の settings.json が見つかりません"
    FAIL=$((FAIL + 1))
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 5. シェル環境チェック
# ---------------------------------------------------------
echo "[5] シェル環境"
case "$(uname -s)" in
  Darwin) RC_FILE="$HOME/.zshrc" ;;
  Linux)  RC_FILE="$HOME/.bashrc" ;;
  *)      RC_FILE="" ;;
esac

if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ] && grep -qF "# === Dotfiles Harness Settings ===" "$RC_FILE"; then
    echo "  ✅ $RC_FILE にハーネス設定の読み込みが存在します"
    PASS=$((PASS + 1))
else
    echo "  ❌ $RC_FILE からハーネス設定が読み込まれていません"
    FAIL=$((FAIL + 1))
fi
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 6. Homebrew セキュリティ設定 (macOS のみ)
# ---------------------------------------------------------
if [ "$(uname -s)" = "Darwin" ]; then
    echo "[6] Homebrew セキュリティ設定"
    if command -v brew >/dev/null 2>&1; then
        brew_check() {
            local label="$1"
            local var="$2"
            local expected="$3"
            local actual
            actual="$(eval echo \"\$$var\")"
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

        brew_check "HOMEBREW_NO_AUTO_UPDATE=1 (自動更新禁止)"     HOMEBREW_NO_AUTO_UPDATE     "1"
        brew_check "HOMEBREW_NO_INSECURE_REDIRECT=1 (MITM対策)"   HOMEBREW_NO_INSECURE_REDIRECT "1"
        brew_check "HOMEBREW_NO_ANALYTICS=1 (テレメトリ無効)"     HOMEBREW_NO_ANALYTICS       "1"
        brew_check "HOMEBREW_CASK_OPTS=--require-sha (SHA必須)"   HOMEBREW_CASK_OPTS          "--require-sha"
    else
        echo "  ⚠️ Homebrew がインストールされていません。"
    fi
    echo "---------------------------------------------------------"
fi
echo "========================================================="
echo "結果: ✅ $PASS 件成功 / ❌ $FAIL 件失敗"

[ "$FAIL" -eq 0 ]