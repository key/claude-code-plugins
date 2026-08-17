# madr-toolkit

ADR（Architecture Decision Record）の作成・改訂・supersede と、コンテキスト無しレビューを提供する。

## 提供するもの

| 種類 | 名前 | 役割 |
|---|---|---|
| スキル | `manage-adr` | 定型レイアウト・記載ルールに従って ADR を作成・改訂・supersede する |
| スキル | `review-adr` | レビュー対象を特定して `adr-reviewer` に委譲し、報告を中継する薄いフロントエンド |
| エージェント | `adr-reviewer` | 完成した ADR をコンテキスト無しでレビューする（レイアウト・frontmatter・記載ルール違反を severity + 修正案つきで指摘） |

## フォーマット

- **frontmatter**: [MADR](https://adr.github.io/madr/) 準拠 + `tags` 拡張
  （`status` / `date` / `decision-makers` / `tags`）。YAML frontmatter の採用は MADR 自身の
  [ADR-0013](https://adr.github.io/madr/decisions/0013-use-yaml-front-matter-for-meta-data.html) による。
  id はファイル名（`NNNN-slug.md`）、タイトルは H1、supersede は `status` 値で表現する
- **本文レイアウト**: 概要 → 背景 → 決定内容 → 採用する利点 → 受け入れるトレードオフ →
  候補案と却下理由（候補ごとにサブセクション） → 見直し条件

## 記載ルール（要点）

書く: 何を定めるかを冒頭で / なぜ必要になったか / 方針・原則・技術選定（ライセンス込み） /
正直なトレードオフ / 見直し条件

書かない: 具体的な閾値（導出ルール + 一次ソースへのポインタのみ） / 実装詳細・手順書 /
陳腐化する列挙 / Issue・PR 番号 / 付随的な発見・先送り事項 / スケジュール / 作業ログ /
指標の目的化

詳細は [skills/manage-adr/SKILL.md](skills/manage-adr/SKILL.md) を参照。

## 使い方

```text
/madr-toolkit:manage-adr 〜の設計判断を ADR にして
/madr-toolkit:review-adr docs/adr/0009-test-policy.md   # adr-reviewer に委譲
```
