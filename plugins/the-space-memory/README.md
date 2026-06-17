# the-space-memory

ワークスペース横断のナレッジ検索エンジン。ハイブリッド検索（FTS5 +
ベクトル）で過去のメモ・調査・セッションログを検索し、プロンプトに
自動で文脈を注入する。

検索・索引付けの実体は別配布の **`tsm` CLI**
（[the-space-memory](https://github.com/key/the-space-memory)）。
このプラグインは `tsm` を呼び出すフック／スキル／エージェントの薄い
ラッパー。

## 必要ツール

- [`tsm`](https://github.com/key/the-space-memory) CLI（**別途インストールが必要**。
  未導入ならフックは無言でスキップ）
- `jq`

`tsm` が `PATH` 上にあればそれを使う。無ければ
`${CLAUDE_PLUGIN_ROOT}/bin/tsm` にフォールバックする（このリポジトリには
バイナリを同梱していないので、通常は `PATH` 上の `tsm` を使う）。

## 挙動

3 つのフックで動く。いずれも `CLAUDE_PROJECT_DIR` をプロジェクトルート
（= `tsm.toml` の `project_root`）として扱い、プロジェクト外のパスや
空クエリはスキップする。

- **`UserPromptSubmit`** — クエリで `tsm search` し、ヒットを
  `<knowledge_search>` として context に注入（`search.sh`）
- **`PostToolUse` (`Edit`/`Write`)** — 対象が `*.md` かつプロジェクト内なら
  `tsm index` で索引付け（`index-file.sh`）
- **`Stop`** — そのセッションの JSONL を `tsm ingest-session` で取り込む
  （`ingest.sh`）

## スキル / エージェント

- `the-space-memory:search` — 手動でナレッジ検索する（`tsm search`）
- `the-space-memory:doctor` — デーモン・埋め込み器・DB の健全性チェック
- `deep-research` エージェント — 複数クエリ + 全文読みで深掘り調査する

## セットアップ

1. `tsm` CLI をインストールして `PATH` を通す
2. プロジェクトルートに `tsm.toml` を置き `project_root` を設定する
3. デーモンを起動: `tsm daemon start`（フック経由でも自動起動される）
4. 動作確認: `tsm doctor -f json` または `/the-space-memory:doctor`

## 環境変数

| 変数 | 既定 | 意味 |
|---|---|---|
| `TSM_SNIPPET_BUDGET` | `1000` | 検索スニペットの合計文字数の上限 |
| `TSM_HOOK_DEBUG` | （未設定） | セット時のみデバッグログを出力（後述） |

`TSM_HOOK_DEBUG` をセットすると `search.sh` が
`${TMPDIR:-/tmp}/tsm-hook-search.<uid>.log`（0600）に記録する。
生のプロンプトを含むため既定では無効。

## トラブルシューティング

`tsm doctor`（または `/the-space-memory:doctor`）で確認する。

| 症状 | 対処 |
|---|---|
| 検索が空振りする | `tsm doctor` で確認し `tsm backfill` で再生成 |
| 索引されない | `CLAUDE_PROJECT_DIR` がルートを指すか確認 |
| デーモンが落ちている | `tsm daemon start` |
