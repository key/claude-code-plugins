# worktree-guard plugin — Design

- **Date**: 2026-06-22
- **Status**: Draft
- **Author**: key (with Claude)

## Purpose

git worktree を使うリポジトリで、エージェント（Claude）が起こしがちな 3 つの事故を
`PreToolUse(Bash)` フックで未然に防ぐ Claude Code プラグイン。`key/claude-code-plugins`
マーケットプレイスに汎用プラグインとして追加する。

防ぎたい失敗モード（worktree 運用で頻発）:

1. **作成ベースの汚染** — `git worktree add` を現在の HEAD（別ブランチ・未 push 状態）
   から切ってしまい、無関係なコミットが最初から乗る。
2. **間違った場所で作業** — 共有 primary checkout で誤ってコミットし、意図しない
   ブランチに乗る。
3. **他の変更の混入** — `git add -A` 等で無関係な変更をまとめて stage し、コミットに
   紛れ込む。

## Scope / Non-goals

- 対象は **特定リポジトリに限定しない**（汎用）。ただし誤検知を避けるため、ガードは
  **対象 repo が linked worktree を使っている場合にのみ**作動する（後述の活性化条件）。
- セキュリティ境界ではない。**事故防止のための best-effort backstop** であり、巧妙に
  組まれたコマンドの回避までは保証しない。
- 人間の手動操作は対象外（Claude Code の hook なので、Claude のツール実行のみに作用）。
- git 以外のコマンド、解析不能なコマンドはブロックしない（no-op）。

## Activation

フックは PreToolUse(Bash) で全 Bash コマンドを受けるが、次を満たすときのみ判定する:

- コマンドが git 操作である。
- 対象 repo（解決方法は後述）が **linked worktree を持つ**
  （`git worktree list` が 2 エントリ以上、または primary/linked の判定が成立）。
  - ルール 3（`git worktree add`）のみ例外で、worktree 作成行為そのものなので常時判定。

単一 checkout の通常リポジトリでは（worktree 未使用なので）ルール 1・2 は一切作動せず、
誤検知ゼロ。

## Rules

| # | 失敗モード | 検知 | 既定 |
|---|---|---|---|
| 1 | 間違った場所 | `git commit`（または `-a`/`-am`）の対象 repo dir が **primary checkout**（`git rev-parse --git-dir` == `--git-common-dir`）かつ linked worktree が存在 → ブロック | on |
| 2 | 変更の混入 | linked worktree 使用 repo で `git add -A` / `git add .` / `git add --all` / `git commit -a`(`-am`) → ブロック（明示 stage を促す） | on |
| 3 | ベース汚染 | `git worktree add` に**明示のベース ref が無い**（末尾 commit-ish 省略＝現在 HEAD 派生）→ ブロック（`origin/<default>` 等の明示を促す）。ベースを明示すれば意図的な非 default 派生も許可 | on |

ブロックは **exit 2** + stderr に理由と回避策を出力（Claude が読んで修正できる文面）。
各ルールは `userConfig` で個別に無効化できる。

## Plugin structure

`secret-scan` プラグインに倣う:

```text
plugins/worktree-guard/
├── .claude-plugin/plugin.json   # name/description/version/userConfig
├── hooks/hooks.json             # PreToolUse: Bash → scripts/guard.sh
├── hooks/scripts/guard.sh       # ガード本体（bash）
└── README.md
```

`.claude-plugin/marketplace.json` に 1 エントリ、ルート `README.md` のプラグイン表に
1 行追加する。

### hooks.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard.sh\"" }
        ]
      }
    ]
  }
}
```

### userConfig（plugin.json）

| キー | 既定 | 意味 |
|---|---|---|
| `block_primary_commit` | `true` | ルール 1 |
| `block_bulk_add` | `true` | ルール 2 |
| `require_worktree_base` | `true` | ルール 3 |
| `fail_mode` | `open` | 依存（git）欠如・判定不能時の挙動。`open`=許可（誤検知回避優先）/ `closed`=ブロック |

`fail_mode` の既定を `open` にする理由: 本プラグインは事故防止の backstop であり、判定
できないコマンドまでブロックすると通常作業の妨げが大きい。secret-scan（セキュリティ用途
で既定 `closed`）とは目的が異なる。

## guard.sh の処理

1. stdin の hook JSON を読み、`.tool_input.command`（実行予定の Bash 文字列）を取得。
   `jq` が無ければ `fail_mode` に従う。
2. コマンドから **対象 repo dir** を解決する（best-effort）:
   - `git -C <path> ...` の `<path>`、無ければ先頭 `cd <path> &&` の `<path>`、
     無ければフックの実行 CWD。
   - 複数 git 呼び出しの連結など、単一 git 操作として確信を持てない形は **no-op（exit 0）**。
3. git サブコマンドを判定（`commit` / `add` / `worktree add`）。対象外は exit 0。
4. ルール 3 以外は、対象 repo dir で linked worktree の有無を確認
   （`git -C <dir> rev-parse --git-dir`/`--git-common-dir` と `git -C <dir> worktree list`）。
   worktree 未使用なら exit 0。
5. 各ルールを `userConfig`（環境変数で渡る想定）で gating して判定。違反なら exit 2 +
   理由を stderr。
6. 上記いずれにも該当しなければ exit 0。

**設計原則**: 確信を持って違反と判定できた場合のみブロックする。解析の曖昧さは
「ブロックしない」側に倒す（誤検知最小）。

## Testing

`test/` にケース別のシェルテスト（既存プラグインのテスト方式に合わせる）。最低限:

- ルール 1: primary checkout での `commit` をブロック / linked worktree での `commit` を許可 /
  worktree 未使用 repo の primary `commit` を許可。
- ルール 2: `git add -A` / `git add .` / `commit -am` をブロック / `git add <file>` を許可 /
  worktree 未使用 repo では許可。
- ルール 3: `git worktree add <path>`（ベース無し）をブロック /
  `git worktree add <path> origin/main` を許可。
- 解析: `git -C <path> ...` と `cd <path> && git ...` の対象解決 / 解析不能は no-op。
- userConfig: 各ルール無効化で素通り。
- fail_mode: `jq`/`git` 欠如時の open/closed。

各テストは一時的な git repo（必要なら worktree も）を作って検証し、外部状態に依存しない。

## Out of scope (follow-ups)

- 共有 `.git/hooks` の bleed 検知（今回の失敗モードからは除外）。
- 人間の手動 git 操作のガード（git 側 hook が必要、本プラグインの範囲外）。
