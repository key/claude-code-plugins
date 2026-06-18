# lint-yaml

YAML (`*.yml` / `*.yaml`) を編集するたび ryl または yamllint で lint する PostToolUse フックプラグイン。

## 必要ツール

いずれか 1 つ（優先順位 `ryl` > `yamllint`）。どちらも無ければ何もしない。

- [`ryl`](https://github.com/owenlamont/ryl)（Rust 製の高速 YAML linter。yamllint 互換）
- [`yamllint`](https://yamllint.readthedocs.io/)
- `jq`

## 挙動

`Edit`/`Write` の後に対象が `*.yml`/`*.yaml` かつプロジェクト内なら lint を実行する。
リンタは `ryl` > `yamllint` の優先順位で選ぶ（capability fallback）:

1. `ryl` があれば実行する。lint できれば（指摘あり／なし）その結果を使う。
2. `ryl` が設定不足などで実行できない場合は `yamllint` にフォールバックする。
3. どちらも使えなければ何もしない（`on_missing_tool` に従って warn / silent）。

lint 指摘があると既定で `exit 2`。整形は行わない。
ryl の「設定が無くて実行不能」は lint 失敗とは区別し、ブロックしない。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | ryl / yamllint がどちらも使えないとき `warn` / `silent` |
| `block_on_error` | `true` | lint 指摘時に `exit 2` でブロック / `false` で警告のみ |

## YAML lint 設定（プロジェクト側に置く）

`yamllint` は組み込みの既定ルールで動くが、**`ryl` は設定が無いと一切ルールを有効化せず実行できない**。
`ryl` を使うなら下記のような `.yamllint`（または `.ryl.toml`）が実質必須。対象ファイルの
ディレクトリから上に向かって探索される。

`.yamllint`:

```yaml
extends: default
rules:
  line-length:
    max: 120
  truthy: disable
  document-start: disable
```
