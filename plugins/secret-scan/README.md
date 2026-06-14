# secret-scan

シークレットが LLM に渡る前にブロックするセキュリティフックプラグイン。

- **UserPromptSubmit**: プロンプト本文を gitleaks でスキャン
- **PreToolUse (Read)**: 読み込もうとしている既存ファイルを gitleaks でスキャン
  （秘密が LLM に渡る前に）
- **PreToolUse (Write)**: これから書く内容（`tool_input.content`）を gitleaks でスキャン（新規ファイルの秘密も捕捉）
- **PreToolUse (Edit)**: 挿入される新文字列（`tool_input.new_string`）を
  gitleaks でスキャン
- **PreToolUse (Grep)**: `tool_input.path` が単一ファイルのとき
  その内容を gitleaks でスキャン
  （ディレクトリ/省略時の全走査は毎回高コストなため行わない）
- **PreToolUse (Bash)**: コマンド文字列を risky パターン（`.env` 読み出し、`id_rsa`、`~/.ssh/`、
  `.aws/credentials` 等）で判定。**この判定は gitleaks 非依存**で常に実行される

検出時は `exit 2` でブロックする。Bash 判定は POSIX ERE（`grep -E`）のみを使い、
macOS の BSD grep でも動く。

## 必要ツール

- [`gitleaks`](https://github.com/gitleaks/gitleaks)
- `jq`

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `fail_mode` | `closed` | gitleaks 未導入時に `closed`（`exit 2` でブロック=fail closed）/ `open`（警告のみ） |

> **注意（fail closed）:** 既定では gitleaks 未導入のままだと UserPromptSubmit と
> 全 PreToolUse が
> `exit 2` でブロックされ、gitleaks を導入するまで操作できなくなります。緩和するには
> `fail_mode` を `open` に設定してください。
