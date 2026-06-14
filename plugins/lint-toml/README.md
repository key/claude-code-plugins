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
