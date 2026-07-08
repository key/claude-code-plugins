# lint-c

C/C++ (`*.c` `*.h` `*.cc` `*.cpp` `*.hpp` `*.cxx` `*.hxx`) を編集するたび
clang-format で自動整形する PostToolUse フックプラグイン。

## 必要ツール

- [`clang-format`](https://clang.llvm.org/docs/ClangFormat.html)（未インストールなら何もしない。
  `.clang-format-ignore` を使う場合は 18 以上）
- `jq`

## 挙動

`Edit`/`Write` の後に対象が C/C++ ソースかつプロジェクト内なら `clang-format -i` で整形。
**プロジェクトに `.clang-format` が見つからない場合は何もしない**
（LLVM デフォルトスタイルで勝手に整形してプロジェクト規約と喧嘩しないため）。
`.clang-format-ignore` は clang-format 本体が尊重する（対象外ファイルは no-op）。

単一ファイルの整形は数十 ms なので編集レイテンシへの影響はほぼ無い。

## 設定

| key | 既定 | 意味 |
|---|---|---|
| `on_missing_tool` | `warn` | clang-format 未導入時に `warn` / `silent` |
| `autofix` | `true` | `-i` で整形 / `false` で `--dry-run --Werror` の check のみ |
| `block_on_error` | `true` | 失敗時に `exit 2` でブロック / `false` で警告のみ |
