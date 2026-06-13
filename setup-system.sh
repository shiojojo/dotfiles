#!/bin/sh
# ============================================================
# システム全体防衛設定スクリプト (Global Harness Setup)
# 目的: OS全体（全ユーザー・全プロセス）に対し、強力なセキュリティ制約
#       (Postinstall拒否、7日検疫、公式固定) を環境変数レベルで強制する。
# 実行権限: root 必須
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ エラー: このスクリプトはシステム全体の設定を変更するため、root ユーザーで実行してください。"
    exit 1
fi

echo "🛡️ システム全体のセキュリティ設定 (Global Harness) を開始します..."

OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
    PROFILE_PATH="/etc/zshenv"
elif [ "$OS_TYPE" = "Linux" ]; then
    PROFILE_PATH="/etc/profile.d/harness-global.sh"
else
    echo "⚠️ 未対応のOSです: $OS_TYPE"
    exit 1
fi

# ============================================================
# グローバル環境変数ブロックの作成
# ============================================================
cat << 'EOF' > /tmp/harness_env.tmp
# === BEGIN Global Harness Settings ===
# Node / npm
export NPM_CONFIG_IGNORE_SCRIPTS="true"
export NPM_CONFIG_MINIMUM_RELEASE_AGE="10080"
export NPM_CONFIG_MINIMUM_RELEASE_AGE_STRICT="true"

# pnpm 11 以降向け (2026年4月仕様変更対応)
export PNPM_CONFIG_MINIMUM_RELEASE_AGE="10080"
export PNPM_CONFIG_MINIMUM_RELEASE_AGE_STRICT="true"

# Python / uv
export UV_EXCLUDE_NEWER="7 days"
export UV_DEFAULT_INDEX="https://pypi.org/simple"
export PIP_REQUIRE_VIRTUALENV="true"
# === END Global Harness Settings ===
EOF

# ============================================================
# 設定ファイルへの適用処理（冪等性の担保）
# ============================================================
if [ "$OS_TYPE" = "Darwin" ]; then
    touch "$PROFILE_PATH"
    
    # 既存の古い設定ブロックを削除
    sed -e '/# === BEGIN Global Harness Settings ===/,/# === END Global Harness Settings ===/d' "$PROFILE_PATH" > /tmp/zshenv.tmp
    mv /tmp/zshenv.tmp "$PROFILE_PATH"

    # 繰り返し実行による空行の蓄積（肥大化）を cat -s で1行に圧縮
    cat -s "$PROFILE_PATH" > /tmp/zshenv.tmp
    mv /tmp/zshenv.tmp "$PROFILE_PATH"

    # 新しい設定ブロックを追記
    echo "" >> "$PROFILE_PATH"
    cat /tmp/harness_env.tmp >> "$PROFILE_PATH"
    echo "  ✅ $PROFILE_PATH にグローバル防衛変数を適用しました。"

elif [ "$OS_TYPE" = "Linux" ]; then
    # Linux環境ではファイルを丸ごと置き換えるだけでクリーンに適用可能
    mv /tmp/harness_env.tmp "$PROFILE_PATH"
    chmod 644 "$PROFILE_PATH"
    echo "  ✅ $PROFILE_PATH にグローバル防衛変数を配置しました。"
fi

rm -f /tmp/harness_env.tmp
echo "🎉 システム設定のセットアップが完了しました。設定を反映させるため、新しいターミナルを開いてください。"