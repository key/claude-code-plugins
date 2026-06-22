#!/usr/bin/env bash
# worktree-guard: PreToolUse(Bash) hook.
#
# Prevents three accidents common when an agent works across git worktrees:
#   1. committing in the shared primary checkout (wrong place)
#   2. staging unrelated changes in bulk (git add -A / commit -a)
#   3. creating a worktree from the current HEAD instead of an explicit base
#
# Best-effort backstop, NOT a security boundary: it blocks only when it can
# confidently identify a violating git command, and stays out of the way
# otherwise (unparseable commands and non-worktree repos pass through).
set -uo pipefail

PLUGIN_NAME="worktree-guard"
FAIL_MODE="${CLAUDE_PLUGIN_OPTION_fail_mode:-open}"
OPT_PRIMARY_COMMIT="${CLAUDE_PLUGIN_OPTION_block_primary_commit:-true}"
OPT_BULK_ADD="${CLAUDE_PLUGIN_OPTION_block_bulk_add:-true}"
OPT_WT_BASE="${CLAUDE_PLUGIN_OPTION_require_worktree_base:-true}"

allow() { exit 0; }

block() {
  echo "[$PLUGIN_NAME] $1" >&2
  echo "[$PLUGIN_NAME] $2" >&2
  exit 2
}

fail_dep() { # $1 = missing dependency
  echo "[$PLUGIN_NAME] $1 not found; worktree guard disabled." >&2
  if [[ "$FAIL_MODE" == "closed" ]]; then
    echo "[$PLUGIN_NAME] fail closed: install $1 or set fail_mode=open." >&2
    exit 2
  fi
  exit 0
}

command -v jq >/dev/null 2>&1 || fail_dep "jq"
command -v git >/dev/null 2>&1 || fail_dep "git"

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$EVENT" == "PreToolUse" && "$TOOL" == "Bash" ]] || allow

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$CMD" ]] || allow

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[[ -n "$HOOK_CWD" ]] || HOOK_CWD="$PWD"

# Resolve a possibly-relative path against a base directory.
resolve() { # $1 = path, $2 = base
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$2" "$1" ;;
  esac
}

# Honor a leading `cd <dir> &&` so the target repo is resolved correctly.
base="$HOOK_CWD"
rest="$CMD"
if [[ "$CMD" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+)[[:space:]]*\&\&[[:space:]]*(.*)$ ]]; then
  base=$(resolve "${BASH_REMATCH[1]}" "$HOOK_CWD")
  rest="${BASH_REMATCH[2]}"
fi

# Only inspect the first command in a chain. Flags relevant to our rules
# (-a / -A / the worktree base) always precede any quoted commit message, so
# truncating at the first &&/;/| never hides a violation — it only avoids
# misattributing later commands.
seg="$rest"
seg="${seg%%&&*}"
seg="${seg%%;*}"
seg="${seg%%|*}"

# Word-split without glob or command substitution (read does not eval).
read -ra TOK <<< "$seg"
[[ "${TOK[0]:-}" == "git" ]] || allow

# Walk past git's global options to find the subcommand and the target dir.
target="$base"
i=1
n=${#TOK[@]}
while (( i < n )); do
  t="${TOK[i]}"
  case "$t" in
    -C) target=$(resolve "${TOK[i+1]:-.}" "$base"); i=$((i + 2)) ;;
    -c) i=$((i + 2)) ;;
    --git-dir=* | --work-tree=* | --namespace=*) i=$((i + 1)) ;;
    --no-pager | -p | --paginate | --no-replace-objects | --bare) i=$((i + 1)) ;;
    --) i=$((i + 1)); break ;;
    -*) i=$((i + 1)) ;;
    *) break ;;
  esac
done
SUB="${TOK[i]:-}"
[[ -n "$SUB" ]] || allow

# ── Rule 3: `git worktree add` must specify an explicit base ───────────────
if [[ "$SUB" == "worktree" && "${TOK[i+1]:-}" == "add" ]]; then
  [[ "$OPT_WT_BASE" == "true" ]] || allow
  # Count positional args after `add`; -b/-B/--reason consume a value.
  positional=0
  j=$((i + 2))
  while (( j < n )); do
    a="${TOK[j]}"
    case "$a" in
      -b | -B | --reason) j=$((j + 2)) ;;
      -*) j=$((j + 1)) ;;
      *) positional=$((positional + 1)); j=$((j + 1)) ;;
    esac
  done
  # Exactly one positional = path only, no base => branches from current HEAD.
  if (( positional == 1 )); then
    block "git worktree add without an explicit base ref branches from the current HEAD." \
      "Specify a base, e.g. \`git worktree add <path> origin/main\` (run \`git fetch\` first)."
  fi
  allow
fi

# ── Rules 1 & 2 apply only to repos that use linked worktrees ──────────────
[[ "$SUB" == "commit" || "$SUB" == "add" ]] || allow

git_dir=$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null) || allow

worktree_count=$(git -C "$target" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
# No linked worktrees => ordinary single-checkout repo => never guard.
(( worktree_count >= 2 )) || allow

# A linked worktree's git dir is `<repo>/.git/worktrees/<name>`; the primary
# checkout's is just `<repo>/.git`. This avoids fragile path normalization.
is_primary=true
case "$git_dir" in */worktrees/*) is_primary=false ;; esac

# ── Rule 1: no commits in the primary checkout when worktrees are in use ───
if [[ "$SUB" == "commit" && "$OPT_PRIMARY_COMMIT" == "true" && "$is_primary" == "true" ]]; then
  block "commit in the primary checkout while linked worktrees exist." \
    "Commit from a worktree instead, so it lands on the intended branch."
fi

# ── Rule 2: stage explicitly; no bulk add / commit -a ─────────────────────
if [[ "$OPT_BULK_ADD" == "true" ]]; then
  if [[ "$SUB" == "add" ]]; then
    j=$((i + 1))
    while (( j < n )); do
      case "${TOK[j]}" in
        -A | --all | . | ./)
          block "bulk staging (git add ${TOK[j]}) can sweep in unrelated changes." \
            "Stage specific paths, e.g. \`git add <file>...\`, after reviewing \`git status\`."
          ;;
      esac
      j=$((j + 1))
    done
  elif [[ "$SUB" == "commit" ]]; then
    j=$((i + 1))
    while (( j < n )); do
      a="${TOK[j]}"
      if [[ "$a" == "--all" || ( "$a" == -* && "$a" != --* && "$a" == *a* ) ]]; then
        block "git commit ${a} stages all tracked changes and can include unrelated edits." \
          "Stage specific paths first, then \`git commit\` without -a."
      fi
      j=$((j + 1))
    done
  fi
fi

allow
