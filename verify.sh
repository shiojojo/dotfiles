#!/usr/bin/env bash
# ============================================================
# Dotfiles 設定監査スクリプト (Harness Engineering)
#
# 目的: グローバルのセキュリティ設定が実際に有効かを検証する。
# ============================================================

# --- スクリプト自身のディレクトリを確実に取得 ---
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ------------------------------------------------------------
# 高速健全性チェックモード (--check)
# .zshrc などから呼び出され、ミリ秒単位でクリティカルな防御網を検証する
# ------------------------------------------------------------
if [ "$1" = "--check" ]; then
    HAS_ERROR=0

    # 1. PATH ガードの生存確認 (POSIX準拠で「先頭」にあるか厳格チェック)
    case "$PATH" in
        "$DOTFILES_DIR/bin:"* | "$DOTFILES_DIR/bin")
            # 正常: 先頭に設定されている
            ;;
        *)
            HAS_ERROR=1
            ;;
    esac

    # 2. クリティカルな環境変数の確認
    if [ "$PIP_REQUIRE_VIRTUALENV" != "true" ]; then
        HAS_ERROR=1
    fi

    # OSごとの防衛設定・履歴保護が有効かチェック
    if [ "$(uname -s)" = "Darwin" ]; then
        if [ "$HOMEBREW_NO_AUTO_UPDATE" != "1" ] || [ -z "$HISTORY_IGNORE" ]; then
            HAS_ERROR=1
        fi
    elif [ "$(uname -s)" = "Linux" ]; then
        if [ -z "$HISTIGNORE" ]; then
            HAS_ERROR=1
        fi
    fi

    # 3. リンクと include の生存確認
    if [ ! -f "$HOME/.gitconfig" ] || ! grep -qF "$DOTFILES_DIR/git/config_shared" "$HOME/.gitconfig" >/dev/null 2>&1; then
        HAS_ERROR=1
    fi
    if [ ! -L "$HOME/.config/uv/uv.toml" ]; then
        HAS_ERROR=1
    fi

    # 4. bin/ の Git 整合性チェック (改ざん・不審ファイルの検知)
    if command -v git >/dev/null 2>&1; then
        if ! git -C "$DOTFILES_DIR" diff --quiet HEAD -- bin/ > /dev/null 2>&1; then
            HAS_ERROR=1
        fi
        if [ -n "$(git -C "$DOTFILES_DIR" ls-files --others --exclude-standard bin/)" ]; then
            HAS_ERROR=1
        fi
    fi

    # エラーがあれば 1 (異常) を返し、なければ 0 (正常) で静かに終了
    exit $HAS_ERROR
fi

# ============================================================
# フル監査モード (通常実行: ./verify.sh)
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

# pnpm 11 のマップ/配列仕様に対応した allow-builds 専用チェック
check_pnpm_allow_builds() {
    local actual
    actual="$(pnpm config get allow-builds --global 2>/dev/null)"

    # 文字列の空 ""、配列の空 "[]"、マップの空 "{}" のいずれも許可
    if [ "$actual" = "" ] || [ "$actual" = "[]" ] || [ "$actual" = "{}" ]; then
        echo "  ✅ allow-builds (postinstall全拒否)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ allow-builds (postinstall全拒否)"
        echo "       期待値: '' または '[]' または '{}'"
        echo "       実際値: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

git_check() {
    local label="$1"
    local key="$2"
    local expected="$3"
    local actual
    # --includes を追加して include 先の設定も取得対象にする
    actual="$(git config --global --includes --get "$key" 2>/dev/null || echo "")"

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

echo "🔍 ハーネス設定のフル監査を開始します..."
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
    check_pnpm_allow_builds
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

    if [ -L "$UV_TOML" ]; then
        echo "  ✅ uv.toml はシンボリックリンクです ($(readlink "$UV_TOML"))"
        PASS=$((PASS + 1))
    else
        echo "  ❌ uv.toml がシンボリックリンクではありません"
        FAIL=$((FAIL + 1))
    fi

    uv_check "exclude-newer (7日検疫)"  exclude-newer  "7 days"
    uv_check "url (公式レジストリ固定)"  url             "https://pypi.org/simple"

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
    GITCONFIG_SHARED="$DOTFILES_DIR/git/config_shared"

    if git config --global --get-all include.path 2>/dev/null | grep -qF "$GITCONFIG_SHARED"; then
        echo "  ✅ ~/.gitconfig に共通設定 ($GITCONFIG_SHARED) が include されています"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ~/.gitconfig に共通設定の include が設定されていません"
        FAIL=$((FAIL + 1))
    fi

    if [ -L "$HOME/.gitignore_global" ]; then
        echo "  ✅ ~/.gitignore_global はシンボリックリンクです ($(readlink "$HOME/.gitignore_global"))"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ~/.gitignore_global がシンボリックリンクではありません"
        FAIL=$((FAIL + 1))
    fi

    # --includes を追加して include 先の設定も取得対象にする
    EXCLUDES="$(git config --global --includes --get core.excludesfile || echo "")"
    if [ "$EXCLUDES" = "$HOME/.gitignore_global" ] || [ "$EXCLUDES" = "~/.gitignore_global" ]; then
        echo "  ✅ core.excludesfile ($EXCLUDES)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ core.excludesfile (~/.gitignore_global が設定されていません)"
        FAIL=$((FAIL + 1))
    fi

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

    # ブール値・文字列問わず、統一された検証関数
    vsc_check() {
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

    vsc_check "extensions.autoUpdate=false (時間差検疫)" "extensions.autoUpdate" "false" '"extensions\.autoUpdate"[[:space:]]*:[[:space:]]*false'
    vsc_check "extensions.autoCheckUpdates=true" "extensions.autoCheckUpdates" "true" '"extensions\.autoCheckUpdates"[[:space:]]*:[[:space:]]*true'
    vsc_check "security.workspace.trust.enabled=true" "security.workspace.trust.enabled" "true" '"security\.workspace\.trust\.enabled"[[:space:]]*:[[:space:]]*true'
    vsc_check "security.workspace.trust.emptyWindow=false" "security.workspace.trust.emptyWindow" "false" '"security\.workspace\.trust\.emptyWindow"[[:space:]]*:[[:space:]]*false'
    vsc_check "security.workspace.trust.untrustedFiles=prompt" "security.workspace.trust.untrustedFiles" "prompt" '"security\.workspace\.trust\.untrustedFiles"[[:space:]]*:[[:space:]]*"prompt"'
    vsc_check "update.mode=manual" "update.mode" "manual" '"update\.mode"[[:space:]]*:[[:space:]]*"manual"'
    vsc_check "telemetry.telemetryLevel=off" "telemetry.telemetryLevel" "off" '"telemetry\.telemetryLevel"[[:space:]]*:[[:space:]]*"off"'
    vsc_check "workbench.enableExperiments=false" "workbench.enableExperiments" "false" '"workbench\.enableExperiments"[[:space:]]*:[[:space:]]*false'
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

# POSIX準拠の PATH 先頭チェック
case "$PATH" in
    "$DOTFILES_DIR/bin:"* | "$DOTFILES_DIR/bin")
        echo "  ✅ dotfiles/bin が PATH の先頭に設定されています"
        PASS=$((PASS + 1))
        ;;
    *)
        echo "  ❌ dotfiles/bin が PATH の先頭に設定されていません"
        FAIL=$((FAIL + 1))
        ;;
esac

# 履歴保護設定のチェック
if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$HISTORY_IGNORE" = "(*TOKEN*|*SECRET*|*PASSWORD*|*KEY*|*API_KEY*|*AUTH*)" ]; then
        echo "  ✅ HISTORY_IGNORE (履歴保護) が正しく設定されています"
        PASS=$((PASS + 1))
    else
        echo "  ❌ HISTORY_IGNORE (履歴保護) が設定されていません"
        FAIL=$((FAIL + 1))
    fi
elif [ "$(uname -s)" = "Linux" ]; then
    if [ "$HISTIGNORE" = "*TOKEN*:*SECRET*:*PASSWORD*:*KEY*:*API_KEY*:*AUTH*" ]; then
        echo "  ✅ HISTIGNORE (履歴保護) が正しく設定されています"
        PASS=$((PASS + 1))
    else
        echo "  ❌ HISTIGNORE (履歴保護) が設定されていません"
        FAIL=$((FAIL + 1))
    fi
    if [ "$HISTCONTROL" = "ignoreboth" ]; then
        echo "  ✅ HISTCONTROL (重複・スペース無視) が正しく設定されています"
        PASS=$((PASS + 1))
    else
        echo "  ❌ HISTCONTROL (重複・スペース無視) が設定されていません"
        FAIL=$((FAIL + 1))
    fi
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

# ---------------------------------------------------------
# 7. PATHシム (bin/) の Git 整合性チェック
# ---------------------------------------------------------
echo "[7] PATHシム (bin/) の Git 整合性"

if command -v git >/dev/null 2>&1; then
    if git -C "$DOTFILES_DIR" diff --quiet HEAD -- bin/ > /dev/null 2>&1; then
        echo "  ✅ 既存のシムスクリプトは改ざんされていません"
        PASS=$((PASS + 1))
    else
        echo "  ❌ 既存のシムスクリプトが改ざんされています"
        FAIL=$((FAIL + 1))
    fi

    UNTRACKED_FILES=$(git -C "$DOTFILES_DIR" ls-files --others --exclude-standard bin/)
    if [ -z "$UNTRACKED_FILES" ]; then
        echo "  ✅ 不審な新規ファイルの混入はありません"
        PASS=$((PASS + 1))
    else
        echo "  ❌ bin/ 内に未追跡の不審なファイルが存在します"
        echo "$UNTRACKED_FILES" | sed 's/^/       - /'
        FAIL=$((FAIL + 1))
    fi
else
    echo "  ⚠️ Git がインストールされていないため、整合性チェックをスキップします。"
fi
echo "---------------------------------------------------------"

echo "========================================================="
echo "結果: ✅ $PASS 件成功 / ❌ $FAIL 件失敗"

[ "$FAIL" -eq 0 ]