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

# 引数 1 つが 1 行。すべての行にプラグイン名を付けて stderr へ出す
# (どのフックが止めたのかログから追えるようにするため)。
block() {
  local line
  for line in "$@"; do
    echo "[$PLUGIN_NAME] $line" >&2
  done
  exit 2
}

# 無効化の案内。どのルールを切るのかが分からないと、利用者は設定を
# 探し回ることになる (保存先は /plugin の UI のみ)。
disable_hint() { # $1 = userConfig のキー, $2 = UI 上の表示名
  printf 'To turn this rule off: /plugin -> %s -> "%s" (%s)' "$PLUGIN_NAME" "$2" "$1"
}

# ブロック時の表示用。git 呼び出しを伴うので block 側でだけ使う。
repo_root() { git -C "$target" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$target"; }

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

# Only inspect the first command in a chain. Truncate at the first &&/;/| to
# avoid misattributing a later chained command. This is glob truncation, not a
# shell parser, so a &&/;/| inside a quoted commit message also truncates — that
# only ever drops a detection (an allow), never causes a spurious block, which
# is acceptable for a best-effort guard.
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
      --orphan) allow ;;  # creates a new orphan branch; no base ref applies
      -b | -B | --reason) j=$((j + 2)) ;;
      -*) j=$((j + 1)) ;;
      *) positional=$((positional + 1)); j=$((j + 1)) ;;
    esac
  done
  # Exactly one positional = path only, no base => branches from current HEAD.
  if (( positional == 1 )); then
    block "git worktree add blocked: no base ref given, so the new worktree would branch" \
      "  from whatever HEAD currently is." \
      "  cwd: $target" \
      "Fix: pass an explicit base ref." \
      "      git fetch origin" \
      "      git worktree add <path> origin/main" \
      "      git worktree add <path> -b <new-branch> origin/main" \
      "$(disable_hint require_worktree_base 'Require explicit base for git worktree add')"
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
# checkout's is `<repo>/.git`. Anchor on `/.git/worktrees/` (the structure git
# itself creates) so a repo merely *located* under a path containing the word
# "worktrees" is not misclassified as a linked worktree.
is_primary=true
case "$git_dir" in */.git/worktrees/*) is_primary=false ;; esac

# ── Rule 1: no commits in the primary checkout when worktrees are in use ───
if [[ "$SUB" == "commit" && "$OPT_PRIMARY_COMMIT" == "true" && "$is_primary" == "true" ]]; then
  repo=$(repo_root)
  branch=$(git -C "$target" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ -z "$branch" || "$branch" == "HEAD" ]] && branch="(detached)"
  # 提案コマンドに入れるブランチ名。detached のときは実在しないので伏せる。
  branch_ref="$branch"
  [[ "$branch" == "(detached)" ]] && branch_ref="<branch>"

  # linked worktree だけを "<path> [<branch>]" で並べる。--porcelain の先頭は
  # 常に primary なので落とす (primary を候補に出すと堂々巡りになる)。
  linked=$(git -C "$target" worktree list --porcelain 2>/dev/null | awk '
    /^worktree /  { p = substr($0, 10); next }
    /^branch /    { b = substr($0, 8); sub(/^refs\/heads\//, "", b); print p " [" b "]"; next }
    /^detached$/  { print p " [detached]"; next }
  ' | tail -n +2)

  msg=(
    "commit blocked: this is the PRIMARY checkout of a repo that uses linked worktrees."
    "  repo:   $repo"
    "  branch: $branch"
    "  linked worktrees:"
  )
  while IFS= read -r wt; do
    [[ -n "$wt" ]] && msg+=("    $wt")
  done <<< "$linked"
  msg+=(
    "Why: the primary checkout is shared. A commit here lands on whichever branch it"
    "  happens to have out, and it collides with the worktrees other sessions use."
    "Fix: commit from the worktree that owns the work."
    "  - the branch is already in one of the worktrees above:"
    "      git -C <worktree> commit ..."
    "  - the branch is checked out HERE. A plain 'worktree add' refuses a branch that is"
    "    already checked out, so pass --force, commit there, then clear the primary index:"
    "      git -C $repo worktree add --force <new-worktree-path> $branch_ref"
    "      git -C <new-worktree-path> add <paths>"
    "      git -C <new-worktree-path> commit ..."
    "      git -C $repo reset"
    "$(disable_hint block_primary_commit 'Block commits in the primary checkout')"
  )
  block "${msg[@]}"
fi

# ── Rule 2: stage explicitly; no bulk add / commit -a ─────────────────────
if [[ "$OPT_BULK_ADD" == "true" ]]; then
  if [[ "$SUB" == "add" ]]; then
    j=$((i + 1))
    while (( j < n )); do
      case "${TOK[j]}" in
        -A | --all | . | ./)
          block "bulk staging blocked: 'git add ${TOK[j]}' can sweep in unrelated changes" \
            "  (build output, other sessions' edits, untracked local state)." \
            "  repo: $(repo_root)" \
            "Fix: review 'git status', then stage the paths you mean." \
            "      git add <file> <dir>..." \
            "$(disable_hint block_bulk_add 'Block bulk staging')"
          ;;
      esac
      j=$((j + 1))
    done
  elif [[ "$SUB" == "commit" ]]; then
    # Scan only the leading option cluster. A value-carrying short flag
    # (-m/-F/-C/-c/-t/-S) leads a token whose remainder is its inline value, and
    # the first positional ends the options — stop there so an `-a`/`--all`
    # appearing inside the commit message text cannot trigger a false positive.
    j=$((i + 1))
    while (( j < n )); do
      a="${TOK[j]}"
      case "$a" in
        --all)
          block "commit blocked: 'git commit --all' stages every tracked change, including" \
            "  edits you did not make in this task." \
            "  repo: $(repo_root)" \
            "Fix: stage the paths you mean, then commit without --all." \
            "      git add <file>... && git commit ..." \
            "$(disable_hint block_bulk_add 'Block bulk staging')" ;;
        --*) ;;                # other long flags: never -a
        -[mFCctS]*) break ;;   # value-carrying short flag: remainder is its value
        -*a*)
          block "commit blocked: 'git commit ${a}' stages every tracked change, including" \
            "  edits you did not make in this task." \
            "  repo: $(repo_root)" \
            "Fix: stage the paths you mean, then commit without -a." \
            "      git add <file>... && git commit ..." \
            "$(disable_hint block_bulk_add 'Block bulk staging')" ;;
        -*) ;;                 # other short-flag cluster without -a
        *) break ;;            # first positional ends the option cluster
      esac
      j=$((j + 1))
    done
  fi
fi

allow
