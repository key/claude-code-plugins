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

  # worktree を使う repo を、パスに "worktrees" を含む場所へ置く。
  # primary の git-dir = .../worktrees/proj/.git（/.git/worktrees/ は含まない）。
  mkdir -p "$TMP/worktrees"
  WTP="$TMP/worktrees/proj"
  git init -q "$WTP"
  git -C "$WTP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$WTP" worktree add -q "$TMP/worktrees/proj-wt" -b feat2
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

@test "rule2: blocks git commit --all (long form)" {
  run bash "$GUARD" <<< "$(ev 'git commit --all -m wip' "$WT")"
  [ "$status" -eq 2 ]
}

@test "rule2: does NOT block -a/--all appearing inside the commit message" {
  run bash "$GUARD" <<< "$(ev 'git commit -m "rename -a to --all"' "$WT")"
  [ "$status" -eq 0 ]
}

@test "rule2: does not block when -a follows the -m message (best-effort)" {
  run bash "$GUARD" <<< "$(ev 'git commit -m msg -a' "$WT")"
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

@test "rule3: allows git worktree add --orphan (no base applies)" {
  run bash "$GUARD" <<< "$(ev "git worktree add --orphan -b fresh $TMP/new" "$MAIN")"
  [ "$status" -eq 0 ]
}

# ── primary detection is anchored on the .git structure, not the repo path ──
@test "rule1: blocks primary commit when the repo path contains 'worktrees'" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$WTP")"
  [ "$status" -eq 2 ]
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

# ── 診断メッセージ ─────────────────────────────────────────────────────────
# ブロックの理由と次の一手が、読んだだけで分かること。特に「どのリポジトリか」は
# 複数リポジトリを横断する作業だと本文からは特定できないため必須。
@test "rule1 message: names the repository that was blocked" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$MAIN"* ]]
}

@test "rule1 message: names the branch checked out there" {
  branch=$(git -C "$MAIN" rev-parse --abbrev-ref HEAD)
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  [[ "$output" == *"$branch"* ]]
}

@test "rule1 message: lists the linked worktrees to commit from" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  [[ "$output" == *"$WT"* ]]
  [[ "$output" == *"feat"* ]]
}

@test "rule1 message: lists only the linked worktrees, not the primary" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  # 一覧は "<path> [<branch>]" 形式。primary が混ざると
  # 「そこで commit しろ」という実行不能な指示になる。
  [ "$(grep -c ' \[.*\]$' <<< "$output")" -eq 1 ]
}

@test "rule1 message: explains the --force route when the branch is checked out here" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  # 対象ブランチが primary にある場合、素の worktree add は
  # 「already checked out」で失敗するため、これが無いと手詰まりになる。
  [[ "$output" == *"worktree add --force"* ]]
}

@test "rule1 message: says where to turn the rule off" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  [[ "$output" == *"/plugin"* ]]
  [[ "$output" == *"block_primary_commit"* ]]
}

@test "rule2 message: names the repository and the option" {
  run bash "$GUARD" <<< "$(ev 'git add -A' "$WT")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$WT"* ]]
  [[ "$output" == *"block_bulk_add"* ]]
}

@test "rule3 message: names the target and the option" {
  run bash "$GUARD" <<< "$(ev "git worktree add $TMP/new" "$MAIN")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$MAIN"* ]]
  [[ "$output" == *"require_worktree_base"* ]]
}

@test "every message line carries the plugin prefix" {
  run bash "$GUARD" <<< "$(ev 'git commit -m x' "$MAIN")"
  # 素の行が混ざるとログ上でどのフックの出力か分からなくなる。
  [ "$(grep -cv '^\[worktree-guard\] ' <<< "$output")" -eq 0 ]
}
