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
| `the-space-memory` | クロスワークスペースのナレッジ検索（FTS5 + ベクトル）。`tsm` バイナリは別途インストールが必要 |
| `current-datetime` | UserPromptSubmit 時に現在時刻（Asia/Tokyo）を context として注入する |

## ライセンス

Proprietary。依存ライセンスは MIT, BSD, ISC, Apache-2.0, Unlicense のみ許可。
GPL/LGPL/AGPL/MPL は不可。

## バージョニング & リリース

リリースは [release-please](https://github.com/googleapis/release-please-action) で自動化されている。

- **Conventional Commits** で書く
  - 例: `feat(the-space-memory): ...`, `fix(the-space-memory): ...`
  - scope はプラグイン名（=ディレクトリ名）にする
  - `feat:` → minor、`fix:`/`perf:` → patch
  - `!` または `BREAKING CHANGE:` → major
  - 1.0.0 未満では `feat:` も patch 扱い（`bump-minor-pre-major` 設定）
- main にマージすると release-please がプラグインごとに **Release PR** を自動生成
  - 該当の `plugins/<name>/.claude-plugin/plugin.json` の `version` 更新
  - `plugins/<name>/CHANGELOG.md` の自動生成
  - `.release-please-manifest.json` の更新
- Release PR をマージすると **GitHub Release** と tag が自動作成される
  - tag 形式: `<plugin-name>-v<version>` （例: `the-space-memory-v0.12.0`）

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

## ローカルテスト

```bash
claude --plugin-dir /workspaces/claude-code-plugins/plugins/the-space-memory
```

または、マーケットプレイスとして読み込む:

```bash
claude  # /plugin で claude-code-plugins を追加
```
