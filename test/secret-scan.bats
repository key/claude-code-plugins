#!/usr/bin/env bats
# secret-scan の Bash risky 判定を検証する。
# この分岐は gitleaks に依存しない（gitleaks 不在でもバイパスさせない設計）ため、
# jq さえあれば決定的に通る。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCAN="$REPO_ROOT/plugins/secret-scan/hooks/scripts/secret-scan.sh"
}

bash_event() {  # $1=command → PreToolUse/Bash の JSON を出力
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(jq -Rn --arg c "$1" '$c')"
}

@test "blocks reading .env via bash" {
  run bash "$SCAN" <<< "$(bash_event 'cat .env')"
  [ "$status" -eq 2 ]
}

@test "allows a harmless bash command" {
  run bash "$SCAN" <<< "$(bash_event 'ls -la')"
  [ "$status" -eq 0 ]
}

@test "allows reading only a .env.example" {
  run bash "$SCAN" <<< "$(bash_event 'cat .env.example')"
  [ "$status" -eq 0 ]
}

@test "blocks mixed real .env and example (no bypass)" {
  run bash "$SCAN" <<< "$(bash_event 'cat .env .env.example')"
  [ "$status" -eq 2 ]
}

@test "blocks reading an ssh private key" {
  run bash "$SCAN" <<< "$(bash_event 'cat ~/.ssh/id_rsa')"
  [ "$status" -eq 2 ]
}
