#!/usr/bin/env bats
# statusline のアカウントセグメント（📧）を検証する。
# 一時 CLAUDE_CONFIG_DIR に .claude.json を置き、statusline に JSON を流し込む。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SL="$REPO_ROOT/plugins/statusline/scripts/statusline.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# $1=emailAddress → $TMP/.claude.json を作り、その dir を stdout に返す
cfg() {
  jq -n --arg e "$1" '{oauthAccount:{emailAddress:$e}}' > "$TMP/.claude.json"
  printf '%s' "$TMP"
}

# $1=mode, $2=CLAUDE_CONFIG_DIR → statusline を実行し ANSI を剥がした出力を返す
sl() {
  CLAUDE_STATUSLINE_ACCOUNT="$1" CLAUDE_CONFIG_DIR="$2" bash "$SL" \
    <<< '{"cwd":"/","model":{"display_name":"Test"}}' \
    | sed $'s/\033\\[[0-9;]*m//g'
}

# ── 既定（masked） ────────────────────────────────────────────────────────
@test "masked is the default and hides the local part" {
  dir="$(cfg 'mitsukuni.sato@gmail.com')"
  run sl "" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"📧 m***@gmail.com"* ]]
  [[ "$output" != *"mitsukuni.sato"* ]]
}

@test "masked hides the local part length" {
  dir="$(cfg 'ab@example.com')"
  run sl masked "$dir"
  [[ "$output" == *"📧 a***@example.com"* ]]
}

@test "masked hides a single-character local part entirely" {
  dir="$(cfg 'k@example.com')"
  run sl masked "$dir"
  [[ "$output" == *"📧 ***@example.com"* ]]
  [[ "$output" != *"k***"* ]]
}

@test "masked never leaks a value without an @" {
  dir="$(cfg 'not-an-email')"
  run sl masked "$dir"
  [[ "$output" == *"📧 n***"* ]]
  [[ "$output" != *"not-an-email"* ]]
}

# ── 明示モード ───────────────────────────────────────────────────────────
@test "full shows the whole address" {
  dir="$(cfg 'mitsukuni.sato@gmail.com')"
  run sl full "$dir"
  [[ "$output" == *"📧 mitsukuni.sato@gmail.com"* ]]
}

@test "domain shows only the domain" {
  dir="$(cfg 'mitsukuni.sato@gmail.com')"
  run sl domain "$dir"
  [[ "$output" == *"📧 @gmail.com"* ]]
  [[ "$output" != *"mitsukuni.sato"* ]]
}

@test "domain omits the segment when there is no domain" {
  dir="$(cfg 'not-an-email')"
  run sl domain "$dir"
  [[ "$output" != *"📧"* ]]
}

@test "off omits the segment and never reads the config" {
  dir="$(cfg 'mitsukuni.sato@gmail.com')"
  run sl off "$dir"
  [[ "$output" != *"📧"* ]]
  [[ "$output" != *"gmail.com"* ]]
}

@test "an unknown mode falls back to masked" {
  dir="$(cfg 'mitsukuni.sato@gmail.com')"
  run sl bogus "$dir"
  [[ "$output" == *"📧 m***@gmail.com"* ]]
}

# ── 設定が無い場合 ───────────────────────────────────────────────────────
@test "omits the segment when .claude.json is missing" {
  run sl masked "$TMP/nope"
  [ "$status" -eq 0 ]
  [[ "$output" != *"📧"* ]]
}

@test "omits the segment when .claude.json has no account" {
  echo '{}' > "$TMP/.claude.json"
  run sl masked "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"📧"* ]]
}

@test "omits the segment when .claude.json is malformed" {
  echo 'not json{' > "$TMP/.claude.json"
  run sl masked "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"📧"* ]]
}
