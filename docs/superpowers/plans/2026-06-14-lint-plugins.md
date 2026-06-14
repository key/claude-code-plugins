# Lint / secret-scan Plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dev-template の `lint.sh`（5 言語）と `secret-scan.sh` を、言語ごとの独立した Claude Code プラグイン 6 つに分割して `key-claude-code-plugins` マーケットプレイスへ収録する。

**Architecture:** 各プラグインは `plugins/<name>/` 配下に `.claude-plugin/plugin.json`・`hooks/hooks.json`・`hooks/scripts/*.sh`・`README.md` を持つ。linter は PostToolUse(Edit|Write) で対象拡張子のときだけ該当ツールを実行。secret-scan は UserPromptSubmit + PreToolUse(Read|Edit|Write|Bash) で gitleaks スキャン。挙動は公式 `userConfig`（`CLAUDE_PLUGIN_OPTION_*` env で受領）で設定可能。

**Tech Stack:** bash, jq, 各 linter（rumdl / shellcheck / yamllint / ruff / taplo）, gitleaks, release-please, Claude Code plugin spec。

---

## File Structure

新規作成（プラグインごと）:

- `plugins/lint-markdown/{.claude-plugin/plugin.json, hooks/hooks.json, hooks/scripts/lint.sh, README.md}`
- `plugins/lint-shell/{...}`
- `plugins/lint-yaml/{...}`
- `plugins/lint-python/{...}`
- `plugins/lint-toml/{...}`
- `plugins/secret-scan/{.claude-plugin/plugin.json, hooks/hooks.json, hooks/scripts/secret-scan.sh, README.md}`

修正（リポジトリ登録、各タスクで追記）:

- `.claude-plugin/marketplace.json` — `plugins` 配列
- `release-please-config.json` — `packages`
- `.release-please-manifest.json` — version マップ
- `CLAUDE.md` — 「収録プラグイン」表（最終タスク）

**設計メモ（DRY/独立性）:** プラグインは個別配布されるためファイル共有はできない。5 つの `lint.sh` は構造が同一で、先頭の設定行（ツール名・拡張子・整形コマンド有無）だけが異なる。重複は許容し、各スクリプトを小さく保つ。

**検証方針:** linter 本体の有無に依存しない決定的スモークテスト（拡張子不一致 skip・プロジェクト外 skip・file_path 無し skip）＋ `shellcheck` でスクリプト自身を lint＋`jq` で全 JSON の妥当性確認。block 動作や実 lint は環境依存のため手動確認に回す。

---

## Task 1: lint-markdown プラグイン

**Files:**
- Create: `plugins/lint-markdown/.claude-plugin/plugin.json`
- Create: `plugins/lint-markdown/hooks/hooks.json`
- Create: `plugins/lint-markdown/hooks/scripts/lint.sh`
- Create: `plugins/lint-markdown/README.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `release-please-config.json`
- Modify: `.release-please-manifest.json`

- [ ] **Step 1: Create `plugins/lint-markdown/.claude-plugin/plugin.json`**

```json
{
  "name": "lint-markdown",
  "description": "Auto-format and lint Markdown files with rumdl on edit (PostToolUse)",
  "version": "0.1.0",
  "author": {
    "name": "Mitsukuni Sato"
  },
  "repository": "https://github.com/key/claude-code-plugins",
  "license": "MIT",
  "keywords": ["lint", "markdown", "rumdl", "formatter"],
  "userConfig": {
    "on_missing_tool": {
      "type": "string",
      "title": "On missing tool",
      "description": "rumdl が未インストールのとき: warn=毎回 stderr に警告 / silent=無言。既定 warn",
      "default": "warn"
    },
    "autofix": {
      "type": "boolean",
      "title": "Auto-format",
      "description": "check 前に rumdl fmt で自動整形する。既定 true",
      "default": true
    },
    "block_on_error": {
      "type": "boolean",
      "title": "Block on lint error",
      "description": "check 失敗時に exit 2 で編集をブロックし Claude に修正させる。false なら警告のみ。既定 true",
      "default": true
    }
  }
}
```

- [ ] **Step 2: Create `plugins/lint-markdown/hooks/hooks.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lint.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create `plugins/lint-markdown/hooks/scripts/lint.sh`**

```bash
#!/usr/bin/env bash
# lint-markdown: PostToolUse hook — format & lint *.md with rumdl
set -uo pipefail

PLUGIN_NAME="lint-markdown"
TOOL="rumdl"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
AUTOFIX="${CLAUDE_PLUGIN_OPTION_autofix:-true}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

# jq が無い環境ではスキップ
command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

# 対象拡張子以外は担当外
[[ "$FILE" =~ \.md$ ]] || exit 0

# プロジェクト外（memory 等）は触らない
[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

# ツール未導入時
if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

# 整形（autofix 対応言語）
if [[ "$AUTOFIX" == "true" ]]; then
  rumdl fmt "$FILE" >/dev/null 2>&1 || true
fi

# check
if output=$(rumdl check "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
```

- [ ] **Step 4: Create `plugins/lint-markdown/README.md`**

````markdown
# lint-markdown

Markdown (`*.md`) を編集するたび rumdl で自動整形 + lint する PostToolUse フックプラグイン。

## 必要ツール

- [`rumdl`](https://github.com/rvben/rumdl)（未インストールなら何もしない）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.md` かつプロジェクト内なら `rumdl fmt` → `rumdl check` を実行。
check が失敗すると既定で `exit 2`（Claude に修正を促す）。

## 設定（プラグイン有効化時に尋ねられる）

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | rumdl 未導入時に `warn`（毎回警告）/ `silent`（無言） |
| `autofix` | `true` | check 前に `rumdl fmt` で整形 |
| `block_on_error` | `true` | check 失敗時に `exit 2` でブロック / `false` で警告のみ |

## 推奨設定（プロジェクト側に置く）

`.rumdl.toml`:

```toml
[global]
line_length = 120
exclude = ["**/CHANGELOG.md"]
```
````

- [ ] **Step 5: Verify the script with shellcheck and JSON validity**

Run:
```bash
shellcheck plugins/lint-markdown/hooks/scripts/lint.sh
jq empty plugins/lint-markdown/.claude-plugin/plugin.json plugins/lint-markdown/hooks/hooks.json
```
Expected: no shellcheck output (exit 0), no jq error (exit 0).

- [ ] **Step 6: Run deterministic skip-path smoke tests**

Run:
```bash
# (a) wrong extension → skip, no output, exit 0
echo '{"tool_input":{"file_path":"/tmp/x.txt"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-markdown/hooks/scripts/lint.sh; echo "a exit=$?"
# (b) outside project dir → skip, exit 0
echo '{"tool_input":{"file_path":"/etc/x.md"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-markdown/hooks/scripts/lint.sh; echo "b exit=$?"
# (c) missing file_path → skip, exit 0
echo '{"tool_input":{}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-markdown/hooks/scripts/lint.sh; echo "c exit=$?"
```
Expected: `a exit=0`, `b exit=0`, `c exit=0`, with no other stdout/stderr.

- [ ] **Step 7: Register plugin in marketplace.json**

In `.claude-plugin/marketplace.json`, append to the `plugins` array:
```json
{
  "name": "lint-markdown",
  "description": "Auto-format and lint Markdown files with rumdl on edit (PostToolUse)",
  "category": "linter",
  "source": "./plugins/lint-markdown"
}
```

- [ ] **Step 8: Register in release-please-config.json**

In `release-please-config.json`, add to `packages`:
```json
"plugins/lint-markdown": {
  "package-name": "lint-markdown",
  "extra-files": [
    { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
  ]
}
```

- [ ] **Step 9: Register in .release-please-manifest.json**

Add the line:
```json
"plugins/lint-markdown": "0.1.0"
```

- [ ] **Step 10: Validate edited JSON files**

Run:
```bash
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
```
Expected: exit 0, no error.

- [ ] **Step 11: Commit**

```bash
git add plugins/lint-markdown .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
git commit -m "feat(lint-markdown): add rumdl PostToolUse lint plugin"
```

---

## Task 2: lint-shell プラグイン

**Files:**
- Create: `plugins/lint-shell/.claude-plugin/plugin.json`
- Create: `plugins/lint-shell/hooks/hooks.json`
- Create: `plugins/lint-shell/hooks/scripts/lint.sh`
- Create: `plugins/lint-shell/README.md`
- Modify: `.claude-plugin/marketplace.json`, `release-please-config.json`, `.release-please-manifest.json`

注: shellcheck は整形を持たないため `autofix` オプションは無し。

- [ ] **Step 1: Create `plugins/lint-shell/.claude-plugin/plugin.json`**

```json
{
  "name": "lint-shell",
  "description": "Lint shell scripts with shellcheck on edit (PostToolUse)",
  "version": "0.1.0",
  "author": {
    "name": "Mitsukuni Sato"
  },
  "repository": "https://github.com/key/claude-code-plugins",
  "license": "MIT",
  "keywords": ["lint", "shell", "bash", "shellcheck"],
  "userConfig": {
    "on_missing_tool": {
      "type": "string",
      "title": "On missing tool",
      "description": "shellcheck が未インストールのとき: warn=毎回 stderr に警告 / silent=無言。既定 warn",
      "default": "warn"
    },
    "block_on_error": {
      "type": "boolean",
      "title": "Block on lint error",
      "description": "shellcheck 失敗時に exit 2 で編集をブロックし Claude に修正させる。false なら警告のみ。既定 true",
      "default": true
    }
  }
}
```

- [ ] **Step 2: Create `plugins/lint-shell/hooks/hooks.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lint.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create `plugins/lint-shell/hooks/scripts/lint.sh`**

```bash
#!/usr/bin/env bash
# lint-shell: PostToolUse hook — lint *.sh with shellcheck
set -uo pipefail

PLUGIN_NAME="lint-shell"
TOOL="shellcheck"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.sh$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

if output=$(shellcheck "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
```

- [ ] **Step 4: Create `plugins/lint-shell/README.md`**

````markdown
# lint-shell

Shell スクリプト (`*.sh`) を編集するたび shellcheck で lint する PostToolUse フックプラグイン。

## 必要ツール

- [`shellcheck`](https://www.shellcheck.net/)（未インストールなら何もしない）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.sh` かつプロジェクト内なら `shellcheck` を実行。
失敗すると既定で `exit 2`。shellcheck は整形を行わないため autofix は無い。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | shellcheck 未導入時に `warn` / `silent` |
| `block_on_error` | `true` | 失敗時に `exit 2` でブロック / `false` で警告のみ |
````

- [ ] **Step 5: Verify the script with shellcheck and JSON validity**

Run:
```bash
shellcheck plugins/lint-shell/hooks/scripts/lint.sh
jq empty plugins/lint-shell/.claude-plugin/plugin.json plugins/lint-shell/hooks/hooks.json
```
Expected: no output, exit 0.

- [ ] **Step 6: Run deterministic skip-path smoke tests**

Run:
```bash
echo '{"tool_input":{"file_path":"/tmp/x.txt"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-shell/hooks/scripts/lint.sh; echo "a exit=$?"
echo '{"tool_input":{"file_path":"/etc/x.sh"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-shell/hooks/scripts/lint.sh; echo "b exit=$?"
echo '{"tool_input":{}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-shell/hooks/scripts/lint.sh; echo "c exit=$?"
```
Expected: `a exit=0`, `b exit=0`, `c exit=0`, no other output.

- [ ] **Step 7: Register plugin in marketplace.json**

Append to `plugins` array:
```json
{
  "name": "lint-shell",
  "description": "Lint shell scripts with shellcheck on edit (PostToolUse)",
  "category": "linter",
  "source": "./plugins/lint-shell"
}
```

- [ ] **Step 8: Register in release-please-config.json**

Add to `packages`:
```json
"plugins/lint-shell": {
  "package-name": "lint-shell",
  "extra-files": [
    { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
  ]
}
```

- [ ] **Step 9: Register in .release-please-manifest.json**

```json
"plugins/lint-shell": "0.1.0"
```

- [ ] **Step 10: Validate edited JSON files**

Run:
```bash
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
```
Expected: exit 0.

- [ ] **Step 11: Commit**

```bash
git add plugins/lint-shell .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
git commit -m "feat(lint-shell): add shellcheck PostToolUse lint plugin"
```

---

## Task 3: lint-yaml プラグイン

**Files:**
- Create: `plugins/lint-yaml/.claude-plugin/plugin.json`
- Create: `plugins/lint-yaml/hooks/hooks.json`
- Create: `plugins/lint-yaml/hooks/scripts/lint.sh`
- Create: `plugins/lint-yaml/README.md`
- Modify: `.claude-plugin/marketplace.json`, `release-please-config.json`, `.release-please-manifest.json`

注: yamllint は整形なし → `autofix` 無し。対象は `*.yml` と `*.yaml`。

- [ ] **Step 1: Create `plugins/lint-yaml/.claude-plugin/plugin.json`**

```json
{
  "name": "lint-yaml",
  "description": "Lint YAML files with yamllint on edit (PostToolUse)",
  "version": "0.1.0",
  "author": {
    "name": "Mitsukuni Sato"
  },
  "repository": "https://github.com/key/claude-code-plugins",
  "license": "MIT",
  "keywords": ["lint", "yaml", "yamllint"],
  "userConfig": {
    "on_missing_tool": {
      "type": "string",
      "title": "On missing tool",
      "description": "yamllint が未インストールのとき: warn=毎回 stderr に警告 / silent=無言。既定 warn",
      "default": "warn"
    },
    "block_on_error": {
      "type": "boolean",
      "title": "Block on lint error",
      "description": "yamllint 失敗時に exit 2 で編集をブロックし Claude に修正させる。false なら警告のみ。既定 true",
      "default": true
    }
  }
}
```

- [ ] **Step 2: Create `plugins/lint-yaml/hooks/hooks.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lint.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create `plugins/lint-yaml/hooks/scripts/lint.sh`**

```bash
#!/usr/bin/env bash
# lint-yaml: PostToolUse hook — lint *.yml/*.yaml with yamllint
set -uo pipefail

PLUGIN_NAME="lint-yaml"
TOOL="yamllint"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.(yml|yaml)$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

if output=$(yamllint "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
```

- [ ] **Step 4: Create `plugins/lint-yaml/README.md`**

````markdown
# lint-yaml

YAML (`*.yml` / `*.yaml`) を編集するたび yamllint で lint する PostToolUse フックプラグイン。

## 必要ツール

- [`yamllint`](https://yamllint.readthedocs.io/)（未インストールなら何もしない）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.yml`/`*.yaml` かつプロジェクト内なら `yamllint` を実行。
失敗すると既定で `exit 2`。整形は行わない。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | yamllint 未導入時に `warn` / `silent` |
| `block_on_error` | `true` | 失敗時に `exit 2` でブロック / `false` で警告のみ |

## 推奨設定（プロジェクト側に置く）

`.yamllint`:

```yaml
extends: default
rules:
  line-length:
    max: 120
  truthy: disable
  document-start: disable
```
````

- [ ] **Step 5: Verify the script with shellcheck and JSON validity**

Run:
```bash
shellcheck plugins/lint-yaml/hooks/scripts/lint.sh
jq empty plugins/lint-yaml/.claude-plugin/plugin.json plugins/lint-yaml/hooks/hooks.json
```
Expected: no output, exit 0.

- [ ] **Step 6: Run deterministic skip-path smoke tests**

Run:
```bash
echo '{"tool_input":{"file_path":"/tmp/x.txt"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-yaml/hooks/scripts/lint.sh; echo "a exit=$?"
echo '{"tool_input":{"file_path":"/etc/x.yml"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-yaml/hooks/scripts/lint.sh; echo "b exit=$?"
echo '{"tool_input":{}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-yaml/hooks/scripts/lint.sh; echo "c exit=$?"
```
Expected: `a exit=0`, `b exit=0`, `c exit=0`, no other output.

- [ ] **Step 7: Register plugin in marketplace.json**

Append to `plugins` array:
```json
{
  "name": "lint-yaml",
  "description": "Lint YAML files with yamllint on edit (PostToolUse)",
  "category": "linter",
  "source": "./plugins/lint-yaml"
}
```

- [ ] **Step 8: Register in release-please-config.json**

Add to `packages`:
```json
"plugins/lint-yaml": {
  "package-name": "lint-yaml",
  "extra-files": [
    { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
  ]
}
```

- [ ] **Step 9: Register in .release-please-manifest.json**

```json
"plugins/lint-yaml": "0.1.0"
```

- [ ] **Step 10: Validate edited JSON files**

Run:
```bash
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
```
Expected: exit 0.

- [ ] **Step 11: Commit**

```bash
git add plugins/lint-yaml .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
git commit -m "feat(lint-yaml): add yamllint PostToolUse lint plugin"
```

---

## Task 4: lint-python プラグイン

**Files:**
- Create: `plugins/lint-python/.claude-plugin/plugin.json`
- Create: `plugins/lint-python/hooks/hooks.json`
- Create: `plugins/lint-python/hooks/scripts/lint.sh`
- Create: `plugins/lint-python/README.md`
- Modify: `.claude-plugin/marketplace.json`, `release-please-config.json`, `.release-please-manifest.json`

注: ruff は整形あり。`autofix=true` で `ruff format`。check は常に `ruff check --fix`（`--fix` の自動修正は block 設定に関わらず行う）。

- [ ] **Step 1: Create `plugins/lint-python/.claude-plugin/plugin.json`**

```json
{
  "name": "lint-python",
  "description": "Auto-format and lint Python files with ruff on edit (PostToolUse)",
  "version": "0.1.0",
  "author": {
    "name": "Mitsukuni Sato"
  },
  "repository": "https://github.com/key/claude-code-plugins",
  "license": "MIT",
  "keywords": ["lint", "python", "ruff", "formatter"],
  "userConfig": {
    "on_missing_tool": {
      "type": "string",
      "title": "On missing tool",
      "description": "ruff が未インストールのとき: warn=毎回 stderr に警告 / silent=無言。既定 warn",
      "default": "warn"
    },
    "autofix": {
      "type": "boolean",
      "title": "Auto-format",
      "description": "check 前に ruff format で自動整形する。既定 true",
      "default": true
    },
    "block_on_error": {
      "type": "boolean",
      "title": "Block on lint error",
      "description": "ruff check 失敗時に exit 2 で編集をブロックし Claude に修正させる。false なら警告のみ。既定 true",
      "default": true
    }
  }
}
```

- [ ] **Step 2: Create `plugins/lint-python/hooks/hooks.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lint.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create `plugins/lint-python/hooks/scripts/lint.sh`**

```bash
#!/usr/bin/env bash
# lint-python: PostToolUse hook — format & lint *.py with ruff
set -uo pipefail

PLUGIN_NAME="lint-python"
TOOL="ruff"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
AUTOFIX="${CLAUDE_PLUGIN_OPTION_autofix:-true}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.py$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

if [[ "$AUTOFIX" == "true" ]]; then
  ruff format "$FILE" >/dev/null 2>&1 || true
fi

if output=$(ruff check --fix "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
```

- [ ] **Step 4: Create `plugins/lint-python/README.md`**

````markdown
# lint-python

Python (`*.py`) を編集するたび ruff で自動整形 + lint する PostToolUse フックプラグイン。

## 必要ツール

- [`ruff`](https://docs.astral.sh/ruff/)（未インストールなら何もしない）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.py` かつプロジェクト内なら `ruff format` → `ruff check --fix` を実行。
check が失敗すると既定で `exit 2`。`--fix` による自動修正は block 設定に関わらず行われる。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | ruff 未導入時に `warn` / `silent` |
| `autofix` | `true` | check 前に `ruff format` で整形 |
| `block_on_error` | `true` | check 失敗時に `exit 2` でブロック / `false` で警告のみ |
````

- [ ] **Step 5: Verify the script with shellcheck and JSON validity**

Run:
```bash
shellcheck plugins/lint-python/hooks/scripts/lint.sh
jq empty plugins/lint-python/.claude-plugin/plugin.json plugins/lint-python/hooks/hooks.json
```
Expected: no output, exit 0.

- [ ] **Step 6: Run deterministic skip-path smoke tests**

Run:
```bash
echo '{"tool_input":{"file_path":"/tmp/x.txt"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-python/hooks/scripts/lint.sh; echo "a exit=$?"
echo '{"tool_input":{"file_path":"/etc/x.py"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-python/hooks/scripts/lint.sh; echo "b exit=$?"
echo '{"tool_input":{}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-python/hooks/scripts/lint.sh; echo "c exit=$?"
```
Expected: `a exit=0`, `b exit=0`, `c exit=0`, no other output.

- [ ] **Step 7: Register plugin in marketplace.json**

Append to `plugins` array:
```json
{
  "name": "lint-python",
  "description": "Auto-format and lint Python files with ruff on edit (PostToolUse)",
  "category": "linter",
  "source": "./plugins/lint-python"
}
```

- [ ] **Step 8: Register in release-please-config.json**

Add to `packages`:
```json
"plugins/lint-python": {
  "package-name": "lint-python",
  "extra-files": [
    { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
  ]
}
```

- [ ] **Step 9: Register in .release-please-manifest.json**

```json
"plugins/lint-python": "0.1.0"
```

- [ ] **Step 10: Validate edited JSON files**

Run:
```bash
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
```
Expected: exit 0.

- [ ] **Step 11: Commit**

```bash
git add plugins/lint-python .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
git commit -m "feat(lint-python): add ruff PostToolUse lint plugin"
```

---

## Task 5: lint-toml プラグイン

**Files:**
- Create: `plugins/lint-toml/.claude-plugin/plugin.json`
- Create: `plugins/lint-toml/hooks/hooks.json`
- Create: `plugins/lint-toml/hooks/scripts/lint.sh`
- Create: `plugins/lint-toml/README.md`
- Modify: `.claude-plugin/marketplace.json`, `release-please-config.json`, `.release-please-manifest.json`

注: taplo は整形あり。`autofix=true` で `taplo fmt`、check は `taplo check`。

- [ ] **Step 1: Create `plugins/lint-toml/.claude-plugin/plugin.json`**

```json
{
  "name": "lint-toml",
  "description": "Auto-format and lint TOML files with taplo on edit (PostToolUse)",
  "version": "0.1.0",
  "author": {
    "name": "Mitsukuni Sato"
  },
  "repository": "https://github.com/key/claude-code-plugins",
  "license": "MIT",
  "keywords": ["lint", "toml", "taplo", "formatter"],
  "userConfig": {
    "on_missing_tool": {
      "type": "string",
      "title": "On missing tool",
      "description": "taplo が未インストールのとき: warn=毎回 stderr に警告 / silent=無言。既定 warn",
      "default": "warn"
    },
    "autofix": {
      "type": "boolean",
      "title": "Auto-format",
      "description": "check 前に taplo fmt で自動整形する。既定 true",
      "default": true
    },
    "block_on_error": {
      "type": "boolean",
      "title": "Block on lint error",
      "description": "taplo check 失敗時に exit 2 で編集をブロックし Claude に修正させる。false なら警告のみ。既定 true",
      "default": true
    }
  }
}
```

- [ ] **Step 2: Create `plugins/lint-toml/hooks/hooks.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/lint.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create `plugins/lint-toml/hooks/scripts/lint.sh`**

```bash
#!/usr/bin/env bash
# lint-toml: PostToolUse hook — format & lint *.toml with taplo
set -uo pipefail

PLUGIN_NAME="lint-toml"
TOOL="taplo"

ON_MISSING="${CLAUDE_PLUGIN_OPTION_on_missing_tool:-warn}"
AUTOFIX="${CLAUDE_PLUGIN_OPTION_autofix:-true}"
BLOCK="${CLAUDE_PLUGIN_OPTION_block_on_error:-true}"

command -v jq >/dev/null 2>&1 || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE" ]] && exit 0

[[ "$FILE" =~ \.toml$ ]] || exit 0

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ "$FILE" != "$CLAUDE_PROJECT_DIR"/* ]] && exit 0

if ! command -v "$TOOL" >/dev/null 2>&1; then
  [[ "$ON_MISSING" == "warn" ]] && echo "[$PLUGIN_NAME] $TOOL が見つからないため skip しました" >&2
  exit 0
fi

if [[ "$AUTOFIX" == "true" ]]; then
  taplo fmt "$FILE" >/dev/null 2>&1 || true
fi

if output=$(taplo check "$FILE" 2>&1); then
  exit 0
fi
echo "$output" >&2
[[ "$BLOCK" == "true" ]] && exit 2
exit 0
```

- [ ] **Step 4: Create `plugins/lint-toml/README.md`**

````markdown
# lint-toml

TOML (`*.toml`) を編集するたび taplo で自動整形 + lint する PostToolUse フックプラグイン。

## 必要ツール

- [`taplo`](https://taplo.tamasfe.dev/)（未インストールなら何もしない）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.toml` かつプロジェクト内なら `taplo fmt` → `taplo check` を実行。
check が失敗すると既定で `exit 2`。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | taplo 未導入時に `warn` / `silent` |
| `autofix` | `true` | check 前に `taplo fmt` で整形 |
| `block_on_error` | `true` | check 失敗時に `exit 2` でブロック / `false` で警告のみ |
````

- [ ] **Step 5: Verify the script with shellcheck and JSON validity**

Run:
```bash
shellcheck plugins/lint-toml/hooks/scripts/lint.sh
jq empty plugins/lint-toml/.claude-plugin/plugin.json plugins/lint-toml/hooks/hooks.json
```
Expected: no output, exit 0.

- [ ] **Step 6: Run deterministic skip-path smoke tests**

Run:
```bash
echo '{"tool_input":{"file_path":"/tmp/x.txt"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-toml/hooks/scripts/lint.sh; echo "a exit=$?"
echo '{"tool_input":{"file_path":"/etc/x.toml"}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-toml/hooks/scripts/lint.sh; echo "b exit=$?"
echo '{"tool_input":{}}' | CLAUDE_PROJECT_DIR=/tmp bash plugins/lint-toml/hooks/scripts/lint.sh; echo "c exit=$?"
```
Expected: `a exit=0`, `b exit=0`, `c exit=0`, no other output.

- [ ] **Step 7: Register plugin in marketplace.json**

Append to `plugins` array:
```json
{
  "name": "lint-toml",
  "description": "Auto-format and lint TOML files with taplo on edit (PostToolUse)",
  "category": "linter",
  "source": "./plugins/lint-toml"
}
```

- [ ] **Step 8: Register in release-please-config.json**

Add to `packages`:
```json
"plugins/lint-toml": {
  "package-name": "lint-toml",
  "extra-files": [
    { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
  ]
}
```

- [ ] **Step 9: Register in .release-please-manifest.json**

```json
"plugins/lint-toml": "0.1.0"
```

- [ ] **Step 10: Validate edited JSON files**

Run:
```bash
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
```
Expected: exit 0.

- [ ] **Step 11: Commit**

```bash
git add plugins/lint-toml .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
git commit -m "feat(lint-toml): add taplo PostToolUse lint plugin"
```

---

## Task 6: secret-scan プラグイン

**Files:**
- Create: `plugins/secret-scan/.claude-plugin/plugin.json`
- Create: `plugins/secret-scan/hooks/hooks.json`
- Create: `plugins/secret-scan/hooks/scripts/secret-scan.sh`
- Create: `plugins/secret-scan/README.md`
- Modify: `.claude-plugin/marketplace.json`, `release-please-config.json`, `.release-please-manifest.json`

- [ ] **Step 1: Create `plugins/secret-scan/.claude-plugin/plugin.json`**

```json
{
  "name": "secret-scan",
  "description": "Block secrets before they reach the LLM: scan prompts/files with gitleaks and Bash commands with risky patterns",
  "version": "0.1.0",
  "author": {
    "name": "Mitsukuni Sato"
  },
  "repository": "https://github.com/key/claude-code-plugins",
  "license": "MIT",
  "keywords": ["security", "secrets", "gitleaks", "hook"],
  "userConfig": {
    "fail_mode": {
      "type": "string",
      "title": "Fail mode when gitleaks is missing",
      "description": "gitleaks 未インストール時: closed=exit 2 でブロック（fail closed）/ open=警告のみ exit 0（fail open）。既定 closed",
      "default": "closed"
    }
  }
}
```

- [ ] **Step 2: Create `plugins/secret-scan/hooks/hooks.json`**

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/secret-scan.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/secret-scan.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Create `plugins/secret-scan/hooks/scripts/secret-scan.sh`**

```bash
#!/usr/bin/env bash
# secret-scan: UserPromptSubmit + PreToolUse hook
# プロンプト/対象ファイルを gitleaks でスキャンし、Bash コマンドは risky パターンで判定。
# 検出時は exit 2 で LLM 到達前にブロックする。
set -uo pipefail

PLUGIN_NAME="secret-scan"
FAIL_MODE="${CLAUDE_PLUGIN_OPTION_fail_mode:-closed}"

# jq が無ければ判定不能 → スキップ
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

# gitleaks 未導入時の扱い（fail_mode）
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[$PLUGIN_NAME] gitleaks が見つかりません。シークレット検出が無効です。" >&2
  if [[ "$FAIL_MODE" == "closed" ]]; then
    echo "[$PLUGIN_NAME] fail closed: gitleaks を導入するまで操作をブロックします。" >&2
    exit 2
  fi
  exit 0
fi

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

block() {
  echo "[$PLUGIN_NAME] 機密情報の疑い: $1" >&2
  echo "[$PLUGIN_NAME] LLM 到達前にブロックしました。該当箇所を除去してから再試行してください。" >&2
  exit 2
}

scan_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  if ! gitleaks detect --no-git --source="$path" --redact --log-level=error >/dev/null 2>&1; then
    block "file=$path"
  fi
}

scan_text() {
  local text="$1"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$text" >"$tmp"
  if ! gitleaks detect --no-git --source="$tmp" --redact --log-level=error >/dev/null 2>&1; then
    rm -f "$tmp"
    block "prompt text"
  fi
  rm -f "$tmp"
}

# 読み込み動詞 + .env（非サンプル）を同一行でマッチ、または既知の機密パス/コマンド
RISKY_BASH_RE='((cat|less|more|head|tail|bat|grep|awk|sed|source)\s+[^|&\n]*\.env(?!\.(example|sample|template|dist|tmpl|tpl))\b|\bprintenv\b|\bid_rsa\b|\bid_ed25519\b|\.pem\b|~/\.ssh/|credentials\.json|\.aws/credentials|\.netrc\b|\.npmrc\b)'

case "$EVENT" in
  UserPromptSubmit)
    PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty')
    [[ -n "$PROMPT" ]] && scan_text "$PROMPT"
    ;;
  PreToolUse)
    case "$TOOL" in
      Read|Edit|Write)
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
        [[ -n "$FILE" ]] && scan_file "$FILE"
        ;;
      Bash)
        CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
        if [[ -n "$CMD" ]] && printf '%s' "$CMD" | grep -qP "$RISKY_BASH_RE"; then
          block "bash command matches risky pattern"
        fi
        ;;
    esac
    ;;
esac

exit 0
```

- [ ] **Step 4: Create `plugins/secret-scan/README.md`**

````markdown
# secret-scan

シークレットが LLM に渡る前にブロックするセキュリティフックプラグイン。

- **UserPromptSubmit**: プロンプト本文を gitleaks でスキャン
- **PreToolUse (Read/Edit/Write)**: 対象ファイルを gitleaks でスキャン
- **PreToolUse (Bash)**: コマンド文字列を risky パターン（`.env` 読み出し、`id_rsa`、`~/.ssh/`、
  `.aws/credentials` 等）で判定

検出時は `exit 2` で LLM 到達前にブロックする。

## 必要ツール

- [`gitleaks`](https://github.com/gitleaks/gitleaks)
- `jq`

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `fail_mode` | `closed` | gitleaks 未導入時に `closed`（`exit 2` でブロック=fail closed）/ `open`（警告のみ） |

> **注意（fail closed）:** 既定では gitleaks 未導入のままだと UserPromptSubmit と全 PreToolUse が
> `exit 2` でブロックされ、gitleaks を導入するまで操作できなくなります。緩和するには
> `fail_mode` を `open` に設定してください。
````

- [ ] **Step 5: Verify the script with shellcheck and JSON validity**

Run:
```bash
shellcheck plugins/secret-scan/hooks/scripts/secret-scan.sh
jq empty plugins/secret-scan/.claude-plugin/plugin.json plugins/secret-scan/hooks/hooks.json
```
Expected: no output, exit 0.

- [ ] **Step 6: Run behavioral smoke tests**

Run (gitleaks がある環境では clean な入力が通ることを確認):
```bash
# clean prompt → 通る（exit 0）
echo '{"hook_event_name":"UserPromptSubmit","prompt":"hello world"}' | bash plugins/secret-scan/hooks/scripts/secret-scan.sh; echo "clean exit=$?"
# risky bash → ブロック（exit 2）※ gitleaks 有無に関わらずパターン判定
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat .env"}}' | bash plugins/secret-scan/hooks/scripts/secret-scan.sh; echo "risky exit=$?"
```
Expected: `clean exit=0`（gitleaks 導入時）、`risky exit=2`（gitleaks 導入時）。
gitleaks 未導入時は `fail_mode` 既定 closed のため両方 `exit 2` になる（その旨を確認）。

- [ ] **Step 7: Register plugin in marketplace.json**

Append to `plugins` array:
```json
{
  "name": "secret-scan",
  "description": "Block secrets before they reach the LLM: scan prompts/files with gitleaks and Bash commands with risky patterns",
  "category": "security",
  "source": "./plugins/secret-scan"
}
```

- [ ] **Step 8: Register in release-please-config.json**

Add to `packages`:
```json
"plugins/secret-scan": {
  "package-name": "secret-scan",
  "extra-files": [
    { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
  ]
}
```

- [ ] **Step 9: Register in .release-please-manifest.json**

```json
"plugins/secret-scan": "0.1.0"
```

- [ ] **Step 10: Validate edited JSON files**

Run:
```bash
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
```
Expected: exit 0.

- [ ] **Step 11: Commit**

```bash
git add plugins/secret-scan .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
git commit -m "feat(secret-scan): add gitleaks-based secret scanning plugin"
```

---

## Task 7: ドキュメント更新と最終検証

**Files:**
- Modify: `CLAUDE.md`（「収録プラグイン」表）

- [ ] **Step 1: Update the plugin table in `CLAUDE.md`**

`## 収録プラグイン` の表に 6 行追記（既存 3 行の下）:

```markdown
| `lint-markdown` | `*.md` を編集時に rumdl で自動整形 + lint（PostToolUse）。rumdl が必要 |
| `lint-shell` | `*.sh` を編集時に shellcheck で lint（PostToolUse）。shellcheck が必要 |
| `lint-yaml` | `*.yml`/`*.yaml` を編集時に yamllint で lint（PostToolUse）。yamllint が必要 |
| `lint-python` | `*.py` を編集時に ruff で自動整形 + lint（PostToolUse）。ruff が必要 |
| `lint-toml` | `*.toml` を編集時に taplo で自動整形 + lint（PostToolUse）。taplo が必要 |
| `secret-scan` | gitleaks でプロンプト/ファイルをスキャンし機密漏洩をブロック。gitleaks が必要 |
```

- [ ] **Step 2: Final whole-repo validation**

Run:
```bash
# 全 plugin.json / hooks.json / ルート JSON の妥当性
find plugins -name '*.json' -print0 | xargs -0 -I{} jq empty {}
jq empty .claude-plugin/marketplace.json release-please-config.json .release-please-manifest.json
# 全 lint/secret スクリプトを shellcheck
find plugins -path '*/hooks/scripts/*.sh' -print0 | xargs -0 shellcheck
# marketplace に 6 新規プラグインが存在することを確認
jq -r '.plugins[].name' .claude-plugin/marketplace.json
```
Expected: jq/shellcheck からエラー無し。最後の出力に `lint-markdown lint-shell lint-yaml lint-python lint-toml secret-scan` を含む 9 プラグイン名が並ぶ。

- [ ] **Step 3: Confirm release-please config/manifest parity**

Run:
```bash
# config の packages キー数と manifest のキー数が一致（9）することを確認
jq '.packages | keys | length' release-please-config.json
jq 'keys | length' .release-please-manifest.json
```
Expected: 両方 `9`。

- [ ] **Step 4: Run rumdl on the docs/README if available**

Run:
```bash
command -v rumdl >/dev/null 2>&1 && rumdl check plugins/*/README.md docs/superpowers/plans/2026-06-14-lint-plugins.md || echo "rumdl 未導入のため skip"
```
Expected: rumdl 導入時は check 通過（または指摘箇所を修正）。未導入なら skip メッセージ。

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: list lint-* and secret-scan plugins in CLAUDE.md"
```

---

## 完了条件

- `plugins/` に 6 つの新規プラグインが存在し、各 `plugin.json`/`hooks.json` が有効な JSON。
- 全フックスクリプトが shellcheck を通過。
- `marketplace.json`・`release-please-config.json`・`.release-please-manifest.json` に 6 プラグインが登録され、config と manifest のキー数が一致。
- `CLAUDE.md` の収録プラグイン表が更新済み。
- 各プラグインのスモークテスト（skip パス）が exit 0 で通過。
```
