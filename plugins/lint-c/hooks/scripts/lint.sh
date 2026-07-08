#!/usr/bin/env bash
# lint-c: PostToolUse hook — format C/C++ sources with clang-format
set -uo pipefail

PLUGIN_NAME="lint-c"
TOOL="clang-format"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
AUTOFIX="${CLAUDE_PLUGIN_OPTION_autofix:-true}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.(c|h|cc|cpp|hpp|cxx|hxx)$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

# 実体が無いファイル（編集後に削除された等）は skip。
# 存在しないファイルで lint が誤って失敗し exit 2 するのを防ぐ。
[[ -f "$FILE" ]] || exit 0

# プロジェクト内に .clang-format が無ければ何もしない。
# LLVM デフォルトスタイルで勝手に整形してプロジェクト規約と喧嘩しないための安全弁。
dir=$(dirname "$FILE")
found=""
while :; do
  if [[ -f "$dir/.clang-format" || -f "$dir/_clang-format" ]]; then
    found=1
    break
  fi
  [[ "$dir" == "$CLAUDE_PROJECT_DIR" || "$dir" == "/" ]] && break
  dir=$(dirname "$dir")
done
[[ -z "$found" ]] && exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

# clang-format 18+ は .clang-format-ignore を自動で尊重する（対象外なら no-op になる）
if [[ "$AUTOFIX" == "true" ]]; then
  cmd=(clang-format --style=file -i "$FILE")
else
  cmd=(clang-format --style=file --dry-run --Werror "$FILE")
fi

if output=$("${cmd[@]}" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
