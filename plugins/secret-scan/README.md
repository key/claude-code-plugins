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
| `fail_mode` | `closed` | 依存（jq/gitleaks）未導入時に `closed`（`exit 2`=fail closed）/ `open`（警告のみ） |

> **注意（fail closed）:** 既定では jq または gitleaks 未導入のままだと
> UserPromptSubmit と全 PreToolUse が `exit 2` でブロックされ、依存を導入するまで
> 操作できなくなります。緩和するには `fail_mode` を `open` に設定してください。

## 限界（過信しないこと）

これは多層防御の一層であり、**唯一の防御線として依存しないこと**。

- **Bash 判定はヒューリスティック**（best-effort）。次のような経路は捕捉しない:
  リダイレクト（`done < .env`）、`env | grep`、`xxd .env`、`. .env`（dot source）、
  `python -c "open('.env')"` 等。逆に過剰ブロック（false positive）もあり得る。
- **gitleaks のデフォルトルール**は `KEY = "value"` 形式は検出するが、地の文に貼られた
  素のトークンは見逃すことがある（UserPromptSubmit のプロンプト走査で特に注意）。
- **カバー範囲**は PreToolUse の Read/Edit/Write/Bash/Grep のみ。NotebookEdit、
  Grep のディレクトリ走査、シンボリックリンク先などは対象外。
