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
