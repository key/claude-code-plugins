# CLAUDE.md

## プロジェクト概要

key 個人用の Claude Code プラグインマーケットプレイス。複数プラグインを束ねて配布する。

## 構成

```text
.claude-plugin/
  marketplace.json         # マーケットプレイスマニフェスト
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json          # プラグインマニフェスト
    agents/                # エージェント定義（自動検出）
    skills/                # スキル定義（自動検出）
    hooks/                 # フック定義（hooks.json + scripts/）
    commands/              # コマンド定義（任意）
```

## 収録プラグイン

| 名前 | 概要 |
|---|---|
| `current-datetime` | UserPromptSubmit 時に現在時刻（システム TZ）を context として注入する |
| `statusline` | env / host / branch / model / context % / rate-limit を 2 行で表示するステータスライン |
| `lint-markdown` | `*.md` を編集時に rumdl で自動整形 + lint（PostToolUse）。rumdl が必要 |
| `lint-shell` | `*.sh` を編集時に shellcheck で lint（PostToolUse）。shellcheck が必要 |
| `lint-yaml` | `*.yml`/`*.yaml` を編集時に yamllint で lint（PostToolUse）。yamllint が必要 |
| `lint-python` | `*.py` を編集時に ruff で自動整形 + lint（PostToolUse）。ruff が必要 |
| `lint-toml` | `*.toml` を編集時に taplo で自動整形 + lint（PostToolUse）。taplo が必要 |
| `secret-scan` | gitleaks でプロンプト/ファイルをスキャンし機密漏洩をブロック。gitleaks が必要 |

## ライセンス

MIT（ルートの `LICENSE` 参照）。各 `plugin.json` の `license` も MIT で統一する。
依存ライセンスは MIT, BSD, ISC, Apache-2.0, Unlicense のみ許可。
GPL/LGPL/AGPL/MPL は不可。

## バージョニング & リリース

リリースは [release-please](https://github.com/googleapis/release-please-action) で自動化されている。

- **Conventional Commits** で書く
  - 例: `feat(statusline): ...`, `fix(lint-markdown): ...`
  - scope はプラグイン名（=ディレクトリ名）にする
  - `feat:` → minor、`fix:`/`perf:` → patch（1.0.0 未満でも `feat:` は minor）
  - `!` または `BREAKING CHANGE:` → major（1.0.0 未満では minor 止まり。`bump-minor-pre-major` 設定）
- main にマージすると release-please がプラグインごとに **Release PR** を自動生成
  - 該当の `plugins/<name>/.claude-plugin/plugin.json` の `version` 更新
  - `plugins/<name>/CHANGELOG.md` の自動生成
  - `.release-please-manifest.json` の更新
- Release PR をマージすると **GitHub Release** と tag が自動作成される
  - tag 形式: `<plugin-name>-v<version>` （例: `statusline-v0.1.1`）

新しいプラグインを追加するときは:

1. `plugins/<new-name>/.claude-plugin/plugin.json` を作る（`"version": "0.1.0"`）
2. `release-please-config.json` の `packages` に新エントリを追加
3. `.release-please-manifest.json` に `"plugins/<new-name>": "0.1.0"` を追加
4. `.claude-plugin/marketplace.json` の `plugins` 配列にも登録

## スキル・エージェント記述規約

- スキルの `description` は英語1行（一覧で見やすくするため）
- エージェントの `description` は英語で書き、日本語のトリガーワードを含める
- 本文（body）は英語（Claude の指示理解精度が高いため）
- スキルはエージェントのフロントエンド（ヒアリング・要件整理・委譲）、エージェントはバックエンド（実行）

## 開発時の注意（フック・CI）

- **編集が PostToolUse フックでブロックされる**: `*.md` 編集時に rumdl が走り、lint 失敗で `exit 2`。
  行は ≤120 文字（`.rumdl.toml` は `line_length=120`、`docs/superpowers/**`・`**/CHANGELOG.md` 除外）。
- **secret-scan が Bash/プロンプトをブロックする**: `cat .env`・`~/.ssh/`・同一行の `less`+`.env` 等の
  risky パターンに反応。テストデータや PR 本文に risky 文字列を直書きせず、変数組み立てや `--body-file` を使う。
- **ステージは明示パスで**: `git add -A` は未追跡の `.tsm/`（ナレッジ DB 等）を巻き込むので使わない。
- **フックのローカルテスト**: `echo '{"tool_input":{"file_path":"x.md"}}' | bash <script>` で stdin に JSON を渡す。
- **CI**（`.github/workflows/ci.yml`）= jq(JSON 検証) + shellcheck + rumdl + `bats test`。`gh pr checks <n>` で確認。
- **PR タイトルは Conventional Commit type 必須**（`pr-title.yml` が強制）。PR は squash マージ。
- **GitHub Actions は commit SHA でピン**（`# vX.Y.Z` コメント併記）。

## ローカルテスト

```bash
claude --plugin-dir <repo>/plugins/<plugin-name>
```

または、マーケットプレイスとして読み込む:

```bash
claude  # /plugin で claude-code-plugins を追加
```
