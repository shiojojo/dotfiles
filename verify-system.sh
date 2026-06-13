#!/usr/bin/env bash
# ============================================================
# システム防衛監査スクリプト (Global Harness Auditor)
# 目的: /etc 以下のセキュリティ設定が全プロセスに強制される状態か監査する。
# 実行権限: root 必須
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ エラー: システム設定の監査のため root 権限で実行してください。"
    exit 1
fi

# --- OSを判定してログインシェル環境を動的に決定 (Linuxでのクラッシュ防止) ---
OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
    SH_EXEC="zsh -lc"
else
    SH_EXEC="bash -lc"
fi

PASS=0
FAIL=0

# ---------------------------------------------------------
# 監査用 汎用関数 (ログインシェル経由での環境変数実効値チェック)
# ---------------------------------------------------------
check_env() {
    local label="$1"
    local key="$2"
    local expected="$3"
    
    # ログインシェルを立ち上げ、ツールが実際に読み込む変数の最終状態を env から直接覗く
    local actual=$(eval "$SH_EXEC 'env | grep ^$key='" | cut -d= -f2)
    
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

echo "🛡️ システム全体防衛設定の監査を開始します..."
echo "========================================================="

# ---------------------------------------------------------
# 1. Node / npm / pnpm 監査
# ---------------------------------------------------------
echo "[1] Node / npm / pnpm システム環境変数"
check_env "NPM_CONFIG_IGNORE_SCRIPTS             = true"    NPM_CONFIG_IGNORE_SCRIPTS             "true"
check_env "NPM_CONFIG_MINIMUM_RELEASE_AGE        = 10080"   NPM_CONFIG_MINIMUM_RELEASE_AGE        "10080"
check_env "NPM_CONFIG_MINIMUM_RELEASE_AGE_STRICT = true"    NPM_CONFIG_MINIMUM_RELEASE_AGE_STRICT "true"

# pnpm 11+ 用環境変数
check_env "PNPM_CONFIG_MINIMUM_RELEASE_AGE        = 10080"   PNPM_CONFIG_MINIMUM_RELEASE_AGE        "10080"
check_env "PNPM_CONFIG_MINIMUM_RELEASE_AGE_STRICT = true"    PNPM_CONFIG_MINIMUM_RELEASE_AGE_STRICT "true"
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 2. Python / uv 監査
# ---------------------------------------------------------
echo "[2] Python / uv システム環境変数"
check_env "PIP_REQUIRE_VIRTUALENV                = true"    PIP_REQUIRE_VIRTUALENV                "true"
check_env "UV_EXCLUDE_NEWER                      = 7 days"  UV_EXCLUDE_NEWER                      "7 days"
check_env "UV_DEFAULT_INDEX                      = PyPI"    UV_DEFAULT_INDEX                      "https://pypi.org/simple"
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 判定結果
# ---------------------------------------------------------
echo "監査結果: ✅ 成功: $PASS / ❌ 失敗: $FAIL"
echo "========================================================="

# 1つでも失敗があれば異常値として終了コード1を返す
[ "$FAIL" -eq 0 ]