#!/usr/bin/env bash
# lint-markdown: PostToolUse hook — format & lint *.md with rumdl
set -uo pipefail

PLUGIN_NAME="lint-markdown"
TOOL="rumdl"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
AUTOFIX="${CLAUDE_PLUGIN_OPTION_autofix:-true}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

# jq が無い環境ではスキップ
command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

# 対象拡張子以外は担当外
[[ "$FILE" =~ \.md$ ]] || exit 0

# プロジェクト外（memory 等）は触らない
[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

# 実体が無いファイル（編集後に削除された等）は skip。
# 存在しないファイルで lint が誤って失敗し exit 2 するのを防ぐ。
[[ -f "$FILE" ]] || exit 0

# ツール未導入時
if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

# 整形（autofix 対応言語）
if [[ "$AUTOFIX" == "true" ]]; then
  rumdl fmt "$FILE" >/dev/null 2>&1 || true
fi

# check
if output=$(rumdl check "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
