#!/bin/bash
# Claude Code statusline script
# Reads JSON from stdin and displays: env | host | dir | branch | worktree | model | ctx | 5h | 7d

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)

# Execution environment detection
env_label=""
if [ "${SANDBOX_RUNTIME:-}" = "1" ] || [ "${CLAUDE_CODE_BUBBLEWRAP:-}" = "1" ]; then
  env_label="Sandbox"
elif [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ]; then
  env_label="DevContainer"
fi

# Working directory (last 2 segments)
cwd=$(echo "$input" | jq -r '.cwd // empty')
[[ -z "$cwd" ]] && cwd="$PWD"
short_dir=$(echo "$cwd" | awk -F'/' '{if(NF>=2) print $(NF-1)"/"$NF; else print $NF}')

# Git branch
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)

# Git worktree name (linked worktrees only; main worktree leaves this empty)
worktree=""
git_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)
case "$git_dir" in
  */worktrees/*) worktree=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)") ;;
esac

# Model display name
model=$(echo "$input" | jq -r '.model.display_name // empty')

# Context used percentage
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Rate limits
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Hostname
host=$(hostname -s 2>/dev/null || hostname)

# ANSI colors
red='\033[31m'
cyan='\033[96m'
blue='\033[94m'
magenta='\033[95m'
yellow='\033[33m'
green='\033[32m'
sep='\033[37m'
reset='\033[0m'

# Fine bar with gradient color (green → yellow → red)
bar_for_pct() {
  local raw="$1"
  local pct=${raw%%.*}
  # 空文字や非数値は 0 として扱う
  if ! [[ "$pct" =~ ^[0-9]+$ ]]; then
    pct=0
  fi
  local color width=10
  if [ "$pct" -ge 80 ] 2>/dev/null; then
    color="$red"
  elif [ "$pct" -ge 50 ] 2>/dev/null; then
    color="$yellow"
  else
    color="$green"
  fi
  local blocks=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
  local filled=$((pct * width))
  local full=$((filled / 100))
  local frac=$(( (filled - full * 100) * 8 / 100 ))
  local bar="" i
  for ((i=0; i<full && i<width; i++)); do bar="${bar}█"; done
  if [ "$full" -lt "$width" ]; then
    if [ "$frac" -gt 0 ]; then
      bar="${bar}${blocks[$frac]}"
    fi
    local remaining=$((width - full - (frac > 0 ? 1 : 0)))
    for ((i=0; i<remaining; i++)); do bar="${bar}░"; done
  fi
  printf '%b' "${color}${bar}${reset} ${pct}%"
}

# Build output: 2 lines
# Line 1: env | user@host:dir | branch
user=$(whoami 2>/dev/null || echo "$USER")
line1=""
if [ -n "$env_label" ]; then line1="📦 ${red}${env_label}${sep} | "; fi
line1="${line1}🏠 ${cyan}${user}${sep}@${cyan}${host}${sep}:${blue}${short_dir}"
if [ -n "$branch" ]; then line1="${line1}${sep} | 🌿 ${magenta}${branch}"; fi
if [ -n "$worktree" ]; then line1="${line1}${sep} | 🌳 ${green}${worktree}"; fi
line1="${line1}${reset}"

# Line 2: model | ctx | 5h | 7d (Fine Bar style)
line2=""
if [ -n "$model" ]; then line2="🤖 ${yellow}${model}${reset}"; fi
if [ -n "$ctx_pct" ]; then line2="${line2}${sep} | ${reset}🧠 ctx $(bar_for_pct "$ctx_pct")"; fi
if [ -n "$five_hour" ]; then line2="${line2}${sep} | ${reset}⏱️ 5h $(bar_for_pct "$five_hour")"; fi
if [ -n "$seven_day" ]; then line2="${line2}${sep} | ${reset}📅 7d $(bar_for_pct "$seven_day")"; fi

printf '%b\n%b' "$line1" "$line2"
