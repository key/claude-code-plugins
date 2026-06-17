#!/usr/bin/env bats
# the-space-memory フックの「対象外なら何もしない」分岐を検証する。
# tsm バイナリより手前で抜ける分岐だけをテストするので、tsm 不在でも通る。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPTS="$REPO_ROOT/plugins/the-space-memory/hooks/scripts"
}

@test "index-file skips non-markdown files" {
  run bash "$SCRIPTS/index-file.sh" <<< '{"tool_input":{"file_path":"/tmp/foo.txt"}}'
  [ "$status" -eq 0 ]
}

@test "search skips too-short queries" {
  run bash "$SCRIPTS/search.sh" <<< '{"prompt":"hi"}'
  [ "$status" -eq 0 ]
}

@test "ingest skips when session_id is missing" {
  run bash "$SCRIPTS/ingest.sh" <<< '{}'
  [ "$status" -eq 0 ]
}
