# lint-python

Python (`*.py`) を編集するたび ruff で自動整形 + lint する PostToolUse フックプラグイン。

## 必要ツール

- [`ruff`](https://docs.astral.sh/ruff/)（未インストールなら何もしない）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.py` かつプロジェクト内なら
`ruff format` → `ruff check --fix` を実行。
check が失敗すると既定で `exit 2`。`--fix` による自動修正は block 設定に関わらず行われる。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | ruff 未導入時に `warn` / `silent` |
| `autofix` | `true` | check 前に `ruff format` で整形 |
| `block_on_error` | `true` | check 失敗時に `exit 2` でブロック / `false` で警告のみ |
