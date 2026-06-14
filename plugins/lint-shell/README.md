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
