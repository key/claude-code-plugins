#!/usr/bin/env bash
# lint-python: PostToolUse hook — format & lint *.py with ruff
set -uo pipefail

PLUGIN_NAME="lint-python"
TOOL="ruff"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
AUTOFIX="${CLAUDE_PLUGIN_OPTION_autofix:-true}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.py$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

# 実体が無いファイル（編集後に削除された等）は skip。
# 存在しないファイルで lint が誤って失敗し exit 2 するのを防ぐ。
[[ -f "$FILE" ]] || exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

# autofix 時のみ整形と --fix を行う。autofix=false なら read-only check に留める
# （rumdl/taplo と同様、autofix がファイル変更可否を一元的に制御する）。
if [[ "$AUTOFIX" == "true" ]]; then
  ruff format "$FILE" >/dev/null 2>&1 || true
  check_cmd=(ruff check --fix "$FILE")
else
  check_cmd=(ruff check "$FILE")
fi

if output=$("${check_cmd[@]}" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
