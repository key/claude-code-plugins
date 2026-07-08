#!/usr/bin/env bats
# lint プラグイン共通の「担当外なら何もしない」挙動を検証する。
# 外部リンタ（rumdl/ruff/...）に依存しない分岐だけをテストするので、
# CI にリンタ本体が無くても決定的に通る。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "lint scripts skip unrelated extensions without output" {
  for p in lint-markdown lint-python lint-shell lint-yaml lint-toml lint-c; do
    run bash "$REPO_ROOT/plugins/$p/hooks/scripts/lint.sh" <<< '{"tool_input":{"file_path":"/tmp/foo.bin"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "lint-markdown skips when file_path is empty" {
  run bash "$REPO_ROOT/plugins/lint-markdown/hooks/scripts/lint.sh" <<< '{"tool_input":{"file_path":""}}'
  [ "$status" -eq 0 ]
}

@test "lint-markdown skips a .md file when CLAUDE_PROJECT_DIR is unset" {
  run env -u CLAUDE_PROJECT_DIR bash "$REPO_ROOT/plugins/lint-markdown/hooks/scripts/lint.sh" <<< '{"tool_input":{"file_path":"/tmp/x.md"}}'
  [ "$status" -eq 0 ]
}

@test "lint-c skips a .c file when the project has no .clang-format" {
  tmp="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$tmp"
  echo 'int main(void){return 0;}' > "$tmp/x.c"
  run env CLAUDE_PROJECT_DIR="$tmp" bash "$REPO_ROOT/plugins/lint-c/hooks/scripts/lint.sh" \
    <<< "{\"tool_input\":{\"file_path\":\"$tmp/x.c\"}}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
