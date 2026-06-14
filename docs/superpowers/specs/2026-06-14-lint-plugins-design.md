# Design: dev-template の linter / secret-scan をプラグイン分割

- **Date**: 2026-06-14
- **Status**: Approved (pending spec review)
- **Source**: `gh:key/dev-template` の `.claude/hooks/lint.sh` と `.claude/hooks/secret-scan.sh`
- **Target**: `key/claude-code-plugins` マーケットプレイス

## 背景 / 目的

`key/dev-template` の `.claude/hooks/lint.sh` は rumdl / shellcheck / yamllint / ruff /
taplo の 5 言語ぶんの linter を 1 つの PostToolUse フックに束ねている。これを
**言語ごとに独立したプラグイン**へ分割し、このマーケットプレイスから配布する。

加えて、linter ではないが `secret-scan.sh`（gitleaks による機密スキャン）も
独立プラグインとして同時に切り出す。

設定ファイル（`.rumdl.toml` / `.yamllint` / gitleaks 設定）はプラグインに**同梱しない**。
これらは利用先プロジェクト側に置くもので、プラグインから自動配置はできない。各 linter は
「プロジェクトに設定があれば使う、無ければデフォルト」で動作する。README に推奨設定を例示するのみ。

## プラグイン一覧（6 つ）

| プラグイン名 | 種別 | 対象拡張子 | フック | 実行内容 | 整形 |
|---|---|---|---|---|---|
| `lint-markdown` | linter | `*.md` | PostToolUse: Edit\|Write | `rumdl fmt` → `rumdl check` | あり |
| `lint-shell` | linter | `*.sh` | PostToolUse: Edit\|Write | `shellcheck` | なし |
| `lint-yaml` | linter | `*.yml` `*.yaml` | PostToolUse: Edit\|Write | `yamllint` | なし |
| `lint-python` | linter | `*.py` | PostToolUse: Edit\|Write | `ruff format` → `ruff check --fix` | あり |
| `lint-toml` | linter | `*.toml` | PostToolUse: Edit\|Write | `taplo fmt` → `taplo check` | あり |
| `secret-scan` | security | (全種) | UserPromptSubmit + PreToolUse | gitleaks スキャン / Bash risky パターン判定 | — |

命名規則: linter は `lint-<lang>`、secret-scan はソース通り `secret-scan`。

## ディレクトリ構造（全プラグイン共通）

既存プラグイン（`statusline` 等）の規約に揃える。

```text
plugins/<name>/
  .claude-plugin/plugin.json     # name/description/version 0.1.0/author/repository/license/keywords + userConfig
  hooks/hooks.json               # フック定義（command は ${CLAUDE_PLUGIN_ROOT} 経由で bash 起動）
  hooks/scripts/<script>.sh      # 実体スクリプト
  README.md                      # 必要ツール・挙動・推奨設定例
```

`hooks.json` の `command` は既存プラグイン同様
`bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<script>.sh` 形式。

## 設定可能化（公式 `userConfig` を使用）

挙動はハードコードせず、`plugin.json` の `userConfig` で有効化時にユーザーへ尋ねる。
出典: <https://code.claude.com/docs/en/plugins-reference.md> (User configuration, L529–566)。

- 各値は実行時に `CLAUDE_PLUGIN_OPTION_<KEY>` 環境変数としてフックのサブプロセスへ渡る。
- 非機密値は `settings.json` の `pluginConfigs[<plugin-id>].options` に保存される。
- スクリプトは `CLAUDE_PLUGIN_OPTION_*` を読んで分岐する。`type: boolean` の値は
  文字列 `"true"` / `"false"` として渡るため、スクリプト側は文字列比較する。
  未設定（プラグイン未設定時）の場合に備え、スクリプト内でデフォルト値へフォールバックする。

### linter プラグイン（lint-*）の options

| key | type | default | 意味 |
|---|---|---|---|
| `on_missing_tool` | string | `warn` | ツール未導入時。`warn`=毎回 stderr に警告し `exit 0` / `silent`=無言で `exit 0` |
| `autofix` | boolean | `true` | 整形ステップの実行可否。md/py/toml のみ対象。shell/yaml は整形が無いので無視 |
| `block_on_error` | boolean | `true` | check 失敗時。`true`=出力を stderr に流し `exit 2`（ブロック）/ `false`=stderr 警告のみ `exit 0` |

### secret-scan プラグインの options

| key | type | default | 意味 |
|---|---|---|---|
| `fail_mode` | string | `closed` | gitleaks 未導入時。`closed`=`exit 2` でブロック（fail closed）/ `open`=強い警告のみ `exit 0`（fail open） |

デフォルトは安全側（`closed`）。

## フック挙動の詳細

### linter スクリプト（各 lint-*）

dev-template `lint.sh` のガードを引き継ぎつつ 1 言語ぶんに簡素化する。

1. `jq` が無ければ `exit 0`（スキップ）。
2. stdin の JSON から `tool_input.file_path` を取得。空/`null` なら `exit 0`。
3. 対象拡張子でなければ `exit 0`（このプラグインの担当外ファイル）。
4. `CLAUDE_PROJECT_DIR` 未設定、またはファイルがプロジェクト外なら `exit 0`
   （memory 等プロジェクト外ファイルを触らない）。
5. linter 本体が未インストール（`command -v` 失敗）の場合、`on_missing_tool` に従う:
   - `warn`（既定）: stderr に `[<name>] <tool> が見つからないため skip` と出して `exit 0`。
   - `silent`: 無言で `exit 0`。
6. 整形対応言語（md/py/toml）で `autofix=true`（既定）なら整形コマンドを実行
   （`rumdl fmt` / `ruff format` / `taplo fmt`）。`autofix=false` なら整形をスキップ。
7. check コマンドを実行（`rumdl check` / `shellcheck` / `yamllint` /
   `ruff check --fix` / `taplo check`）。
8. check 失敗時、`block_on_error` に従う:
   - `true`（既定）: 出力を stderr に流して `exit 2`（Claude が誤りを認識し修正できる）。
   - `false`: 出力を stderr に流すが `exit 0`（非ブロック警告）。

注: `ruff check --fix` は `block_on_error=false` でも自動修正は行う（`--fix` の副作用）。

### secret-scan スクリプト

dev-template `secret-scan.sh` を踏襲。

1. `jq` が無ければ `exit 0`。
2. `gitleaks` が無い場合、`fail_mode` に従う:
   - `closed`（既定）: stderr に「シークレット検出が無効です。gitleaks を導入してください」と
     強く警告して `exit 2`（ブロック）。
   - `open`: 同じ警告を stderr に出すが `exit 0`（非ブロック）。
3. stdin の JSON から `hook_event_name` と `tool_name` を取得し分岐:
   - **UserPromptSubmit**: `prompt` 本文を一時ファイルに書き出して `gitleaks detect` でスキャン。
   - **PreToolUse (Read/Edit/Write)**: `tool_input.file_path` を `gitleaks detect` でスキャン。
   - **PreToolUse (Bash)**: `tool_input.command` を risky 正規表現で判定。
     （`.env` の読み出し、`printenv`、`id_rsa`/`id_ed25519`、`.pem`、`~/.ssh/`、
     `credentials.json`、`.aws/credentials`、`.netrc`、`.npmrc` 等。dev-template の
     `RISKY_BASH_RE` を踏襲）
4. いずれも検出時は stderr に出して `exit 2`（LLM 到達前にブロック）。

#### secret-scan の hooks.json マッチャ

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/secret-scan.sh" }] }
    ],
    "PreToolUse": [
      { "matcher": "Read|Edit|Write|Bash",
        "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/secret-scan.sh" }] }
    ]
  }
}
```

## 設計上の含意

- **ツール未導入なら担当外**: linter は未導入時に既定で skip（warn）するため、6 つ全部入れても
  手元にあるツールの言語だけが効く。
- **secret-scan は fail closed が既定**: gitleaks 未導入のまま有効化すると、`UserPromptSubmit` と
  全 `PreToolUse` が `exit 2` でブロックされ、gitleaks を導入するまで操作できなくなる。これは
  「スキャンできないなら通さない」という意図的な設計。`fail_mode=open` で緩和可能。
- **複数フックの同時発火**: lint-* を複数入れると 1 回の Edit/Write で複数の PostToolUse フックが
  発火するが、各スクリプトは拡張子不一致で即 `exit 0` するため実害は小さい。

## リポジトリ登録（各プラグインにつき 4 箇所）

`CLAUDE.md` の手順に従う。

1. `plugins/<name>/.claude-plugin/plugin.json` を作成（`"version": "0.1.0"`、`userConfig` 込み）。
2. `release-please-config.json` の `packages` に `plugins/<name>` エントリを追加
   （`package-name` と `extra-files`（plugin.json の `$.version`）を既存と同形で）。
3. `.release-please-manifest.json` に `"plugins/<name>": "0.1.0"` を追加。
4. `.claude-plugin/marketplace.json` の `plugins` 配列に登録
   （`name` / `description` / `category` / `source`）。

カテゴリ: linter プラグインは `"category": "linter"`、secret-scan は `"category": "security"`。
ライセンス: 各 plugin.json は既存に倣い `"license": "MIT"`。

`CLAUDE.md` の「収録プラグイン」表にも 6 プラグインを追記する。

## テスト / 検証

- `shellcheck` で各 `*.sh` スクリプト自身を lint（自己適用）。
- `jq` で各 `plugin.json` / `hooks.json` / `marketplace.json` の JSON 妥当性を確認。
- 手動: `claude --plugin-dir plugins/lint-markdown` 等で読み込み、
  対象ファイルを編集してフックが発火することを確認。
- secret-scan は gitleaks 未導入環境で `fail_mode=closed`/`open` の挙動差を確認。

## スコープ外（YAGNI）

- `notify.sh`（通知フック）のプラグイン化。今回は対象外。
- gitleaks / linter 設定ファイルのプラグイン同梱（README 例示のみ）。
- mise / pre-commit 連携。プラグインは「ツールがあれば使う」前提に留める。
