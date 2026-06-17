#!/usr/bin/env bash
set -euo pipefail

FILE=$(jq -r '.tool_input.file_path // empty') || exit 0
[[ -z "$FILE" || "$FILE" == "null" ]] && exit 0

# .md ファイルのみ対象
[[ "$FILE" != *.md ]] && exit 0

# Prefer system-installed tsm over plugin-bundled one
if command -v tsm >/dev/null 2>&1; then
  TSM="tsm"
elif [ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/tsm" ]; then
  TSM="${CLAUDE_PLUGIN_ROOT:-}/bin/tsm"
else
  exit 0
fi

# shellcheck source=plugins/the-space-memory/hooks/scripts/resolve-root.sh
# shellcheck disable=SC1091
. "$(dirname "$0")/resolve-root.sh"
ROOT=$(resolve_root)
cd "$ROOT"

# PROJECT_ROOT（= tsm.toml の project_root）からの相対パスに変換する。
# 絶対パスのときは ROOT を前置から剥がす。
REL_PATH="${FILE#"$ROOT"/}"

# ROOT 配下に変換できなかった場合（プロジェクト外のパス）はスキップ
[ "$REL_PATH" = "$FILE" ] && exit 0

echo "$REL_PATH" | "$TSM" index --files-from-stdin >/dev/null 2>&1
