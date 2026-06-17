# current-datetime

プロンプト送信時（`UserPromptSubmit`）に現在時刻をシステムのタイムゾーンで
context に注入するフックプラグイン。Claude が「今日の日付」「今の時刻」を
正しく扱えるようになる。

## 必要ツール

- `date`（標準コマンド。追加インストール不要）

## 挙動

`UserPromptSubmit` のたびに次の形式の 1 行を出力し、context に注入する:

```xml
<current_datetime date="2026-06-17" time="08:43:20" day="Wed" tz="JST" />
```

タイムゾーンは実行環境のシステム設定に従う（`TZ` 環境変数で上書き可能）。

## 設定

設定項目なし。プラグインを有効化するだけで動く。
