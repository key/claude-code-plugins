#!/usr/bin/env bash
# lint-yaml: PostToolUse hook — lint *.yml/*.yaml with ryl or yamllint
set -uo pipefail

PLUGIN_NAME="lint-yaml"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.(yml|yaml)$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

# 実体が無いファイル（編集後に削除された等）は skip。
# 存在しないファイルで lint が誤って失敗し exit 2 するのを防ぐ。
[[ -f "$FILE" ]] || exit 0

# 失敗（lint 指摘）を報告して BLOCK 設定に応じた exit code を返す。
report_failure() {
  echo "$1" >&2
  [[ "$BLOCK" == "true" ]] && exit 2
  exit 0
}

# 優先順位 ryl > yamllint の capability fallback。
# ryl が「動けた」(0=clean / 1=指摘) ならその結果を使う。
# ryl が exit 2（設定不足等で実行不能）なら yamllint へフォールバックする。
# こうすると ryl を入れただけの未設定プロジェクトでも、従来の yamllint より
# lint が劣化しない（exit 2 のセットアップエラーで誤ってブロックしない）。
if command -v ryl >/dev/null 2>&1; then
  output=$(ryl "$FILE" 2>&1)
  case $? in
    0) exit 0 ;;
    1) report_failure "$output" ;;
    *) : ;;  # 実行不能（設定不足等）→ yamllint へフォールバック
  esac
fi

if command -v yamllint >/dev/null 2>&1; then
  output=$(yamllint "$FILE" 2>&1) && exit 0
  report_failure "$output"
fi

# どちらも使えなかった。
if command -v ryl >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && \
    echo "[$PLUGIN_NAME] ryl が設定不足で実行できず yamllint も無いため skip しました（.yamllint か .ryl.toml が必要）" >&2
else
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] ryl / yamllint が見つからないため skip しました" >&2
fi
exit 0
