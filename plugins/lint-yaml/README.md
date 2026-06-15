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
