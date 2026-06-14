#!/usr/bin/env bash
# secret-scan: UserPromptSubmit + PreToolUse hook
# プロンプト/書き込み内容/読み込み対象を gitleaks でスキャンし、Bash コマンドは risky パターンで判定。
# 検出時は exit 2 で LLM 到達前（または書き込み前）にブロックする。
set -uo pipefail

PLUGIN_NAME="secret-scan"
FAIL_MODE="${CLAUDE_PLUGIN_OPTION_fail_mode:-closed}"

# 依存コマンドが無いとき fail_mode に従う（closed=ブロック / open=警告のみ）
missing_dep() {
  echo "[$PLUGIN_NAME] $1 が見つかりません。シークレット検出が無効です。" >&2
  if [[ "$FAIL_MODE" == "closed" ]]; then
    echo "[$PLUGIN_NAME] fail closed: $1 を導入するまで操作をブロックします（fail_mode=open で緩和可）。" >&2
    exit 2
  fi
  exit 0
}

block() {
  echo "[$PLUGIN_NAME] 機密情報の疑い: $1" >&2
  echo "[$PLUGIN_NAME] ブロックしました。該当箇所を除去してから再試行してください。" >&2
  exit 2
}

# Bash の risky 判定（gitleaks 非依存・POSIX ERE のみ。macOS の BSD grep でも動く）
is_risky_bash() {
  local cmd="$1"
  # 常に危険: 既知の機密パス/コマンド
  local always='(printenv|id_rsa|id_ed25519|\.pem|~/\.ssh/|credentials\.json|\.aws/credentials|\.netrc|\.npmrc)'
  if printf '%s' "$cmd" | grep -Eq "$always"; then
    return 0
  fi
  # .env を読み出すコマンドか？
  local read_env='(cat|less|more|head|tail|bat|grep|awk|sed|source)[[:space:]]+[^|&]*\.env'
  if printf '%s' "$cmd" | grep -Eq "$read_env"; then
    # サンプル参照（.env.example 等）を除去してもなお .env 参照が残れば risky。
    # .env.example のみなら除去後に .env が消えて safe。実 .env と混在する場合は
    # 実 .env が残るため risky（`cat .env .env.example` を許可してしまう穴を防ぐ）。
    local stripped
    stripped=$(printf '%s' "$cmd" | sed -E 's/\.env\.(example|sample|template|dist|tmpl|tpl)//g')
    if printf '%s' "$stripped" | grep -Eq '\.env'; then
      return 0
    fi
    return 1
  fi
  return 1
}

# jq が無ければ JSON を解析できない → fail_mode に従う
command -v jq >/dev/null 2>&1 || missing_dep "jq"

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

# Bash の risky 判定は gitleaks 不要なので先に処理する（gitleaks 不在でもバイパスさせない）
if [[ "$EVENT" == "PreToolUse" && "$TOOL" == "Bash" ]]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
  if [[ -n "$CMD" ]] && is_risky_bash "$CMD"; then
    block "bash command matches risky pattern"
  fi
  exit 0
fi

# 以降のスキャンは gitleaks が必要
command -v gitleaks >/dev/null 2>&1 || missing_dep "gitleaks"

scan_text() {  # $1=対象テキスト $2=ラベル
  local text="$1" label="$2" tmp
  [[ -z "$text" ]] && return 0
  tmp=$(mktemp)
  printf '%s' "$text" >"$tmp"
  if ! gitleaks detect --no-git --source="$tmp" --redact --log-level=error >/dev/null 2>&1; then
    rm -f "$tmp"
    block "$label"
  fi
  rm -f "$tmp"
}

scan_file() {  # $1=ファイルパス
  local path="$1"
  [[ -f "$path" ]] || return 0
  if ! gitleaks detect --no-git --source="$path" --redact --log-level=error >/dev/null 2>&1; then
    block "file=$path"
  fi
}

case "$EVENT" in
  UserPromptSubmit)
    PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
    scan_text "$PROMPT" "prompt text"
    ;;
  PreToolUse)
    case "$TOOL" in
      Read)
        # 読み込もうとしている既存ファイルを走査（秘密が LLM に渡る前にブロック）
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
        [[ -n "$FILE" ]] && scan_file "$FILE"
        ;;
      Write)
        # これから書く内容を走査（新規ファイルの秘密も捕捉）
        CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty')
        scan_text "$CONTENT" "write content"
        ;;
      Edit)
        # 挿入される新文字列を走査
        NEWSTR=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty')
        scan_text "$NEWSTR" "edit new_string"
        ;;
      Grep)
        # path が単一ファイルを指すときのみ走査。
        # ディレクトリ/省略時の全走査は grep 毎に高コストなので行わない（既知の限界）。
        GPATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty')
        [[ -n "$GPATH" && -f "$GPATH" ]] && scan_file "$GPATH"
        ;;
    esac
    ;;
esac

exit 0
