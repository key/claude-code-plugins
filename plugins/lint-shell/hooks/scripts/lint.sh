#!/usr/bin/env bash
# lint-shell: PostToolUse hook — lint *.sh with shellcheck
set -uo pipefail

PLUGIN_NAME="lint-shell"
TOOL="shellcheck"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.sh$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

# 実体が無いファイル（編集後に削除された等）は skip。
# 存在しないファイルで lint が誤って失敗し exit 2 するのを防ぐ。
[[ -f "$FILE" ]] || exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

if output=$(shellcheck "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
