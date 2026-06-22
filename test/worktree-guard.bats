#!/usr/bin/env bats
# worktree-guard のガード判定を検証する。
# 一時 git repo（worktree あり / なし）を作り、PreToolUse/Bash の JSON を流し込む。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$REPO_ROOT/plugins/worktree-guard/hooks/scripts/guard.sh"
  TMP="$(mktemp -d)"

  # worktree を使う repo: primary=$MAIN, linked=$WT
  MAIN="$TMP/main"
  WT="$TMP/wt"
  git init -q "$MAIN"
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$MAIN" worktree add -q "$WT" -b feat

  # 単一 checkout の通常 repo
  SOLO="$TMP/solo"
  git init -q "$SOLO"
  git -C "$SOLO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

teardown() {
  rm -rf "$TMP"
}

# $1=command, $2=cwd → PreToolUse/Bash の JSON
ev() {
  jq -nc --arg c "$1" --arg w "$2" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$w}'
}

# ── Rule 1: primary checkout での commit ──────────────────────────────────
@test "rule1: blocks commit in primary checkout (worktrees exist)" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  [ "$status" -eq 2 ]
}

@test "rule1: allows commit in a linked worktree" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$WT")"
  [ "$status" -eq 0 ]
}

@test "rule1: allows commit in a single-checkout repo (no worktrees)" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$SOLO")"
  [ "$status" -eq 0 ]
}

# ── Rule 2: bulk staging ──────────────────────────────────────────────────
@test "rule2: blocks git add -A in a worktree repo" {
  run bash "$GUARD" <<< "$(ev 'git add -A' "$WT")"
  [ "$status" -eq 2 ]
}

@test "rule2: blocks git add ." {
  run bash "$GUARD" <<< "$(ev 'git add .' "$WT")"
  [ "$status" -eq 2 ]
}

@test "rule2: blocks git commit -am" {
  run bash "$GUARD" <<< "$(ev 'git commit -am wip' "$WT")"
  [ "$status" -eq 2 ]
}

@test "rule2: allows staging a specific path" {
  run bash "$GUARD" <<< "$(ev 'git add src/main.rs' "$WT")"
  [ "$status" -eq 0 ]
}

@test "rule2: allows git add -A in a single-checkout repo" {
  run bash "$GUARD" <<< "$(ev 'git add -A' "$SOLO")"
  [ "$status" -eq 0 ]
}

# ── Rule 3: worktree add base ─────────────────────────────────────────────
@test "rule3: blocks git worktree add without a base" {
  run bash "$GUARD" <<< "$(ev "git worktree add $TMP/new" "$MAIN")"
  [ "$status" -eq 2 ]
}

@test "rule3: blocks git worktree add -b without a base" {
  run bash "$GUARD" <<< "$(ev "git worktree add -b topic $TMP/new" "$MAIN")"
  [ "$status" -eq 2 ]
}

@test "rule3: allows git worktree add with an explicit base" {
  run bash "$GUARD" <<< "$(ev "git worktree add $TMP/new origin/main" "$MAIN")"
  [ "$status" -eq 0 ]
}

@test "rule3: allows git worktree add -b with an explicit base" {
  run bash "$GUARD" <<< "$(ev "git worktree add -b topic $TMP/new origin/main" "$MAIN")"
  [ "$status" -eq 0 ]
}

# ── Target resolution ─────────────────────────────────────────────────────
@test "resolves target via git -C" {
  run bash "$GUARD" <<< "$(ev "git -C $MAIN commit -m x" "$TMP")"
  [ "$status" -eq 2 ]
}

@test "resolves target via leading cd &&" {
  run bash "$GUARD" <<< "$(ev "cd $MAIN && git commit -m x" "$TMP")"
  [ "$status" -eq 2 ]
}

# ── Best-effort: out of scope passes through ──────────────────────────────
@test "allows a non-git command" {
  run bash "$GUARD" <<< "$(ev 'ls -la' "$MAIN")"
  [ "$status" -eq 0 ]
}

@test "does not block when git is not the leading command (best-effort)" {
  run bash "$GUARD" <<< "$(ev 'git status && git add -A' "$MAIN")"
  [ "$status" -eq 0 ]
}

@test "allows non-PreToolUse events" {
  run bash "$GUARD" <<< '{"hook_event_name":"Stop","tool_name":"Bash","tool_input":{"command":"git add -A"},"cwd":"'"$WT"'"}'
  [ "$status" -eq 0 ]
}

# ── userConfig toggles ────────────────────────────────────────────────────
@test "block_bulk_add=false lets git add -A through" {
  CLAUDE_PLUGIN_OPTION_block_bulk_add=false run bash "$GUARD" <<< "$(ev 'git add -A' "$WT")"
  [ "$status" -eq 0 ]
}

@test "require_worktree_base=false lets baseless worktree add through" {
  CLAUDE_PLUGIN_OPTION_require_worktree_base=false run bash "$GUARD" <<< "$(ev "git worktree add $TMP/new" "$MAIN")"
  [ "$status" -eq 0 ]
}

@test "block_primary_commit=false lets primary commit through" {
  CLAUDE_PLUGIN_OPTION_block_primary_commit=false run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  [ "$status" -eq 0 ]
}
