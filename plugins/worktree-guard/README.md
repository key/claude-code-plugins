# worktree-guard

Guard an agent against three mistakes that are easy to make when a repository is
worked on through multiple `git worktree`s. A `PreToolUse` hook inspects each
Bash command and blocks the dangerous ones before they run.

## What it catches

For a repository that **uses linked worktrees**:

1. **Committing in the shared primary checkout.** `git commit` run in the primary
   checkout (not a linked worktree) is blocked — the commit could land on whatever
   branch the primary happens to be on.
2. **Bulk staging.** `git add -A`, `git add .`, and `git commit -a`/`-am` are
   blocked so unrelated changes don't get swept into a commit. Stage explicit
   paths instead.

Always (any repository):

3. **Creating a worktree without an explicit base.** `git worktree add <path>`
   with no base ref branches from the current `HEAD`. Pass a base, e.g.
   `git worktree add <path> origin/main` (after `git fetch`).

Ordinary single-checkout repositories are unaffected: rules 1 and 2 only activate
once a repository has linked worktrees, so there are no false positives in normal
work.

This is a **best-effort backstop**, not a security boundary. It blocks only when
it can confidently identify a violating git command (handling `git -C <dir>` and a
leading `cd <dir> &&`); anything it cannot parse passes through.

## Blocked? read the message

A block prints the repository it resolved, the branch, the linked worktrees you can
commit from, the commands that get you unstuck, and the option that turns the rule
off. The repository matters: the hook resolves the target from `git -C <dir>` or a
leading `cd <dir> &&`, so it is not necessarily the repository the session started in.

Rule 1 has one non-obvious case. If the branch you want is checked out in the primary
itself, a plain `git worktree add` refuses it (`already checked out`) — pass `--force`,
commit from the new worktree, then `git reset` in the primary to clear its index.

## Configuration

Set these in `/plugin` -> `worktree-guard` (the UI is the only place they live; there
is no config file to edit).

| Option | Default | Meaning |
|---|---|---|
| `block_primary_commit` | `true` | Rule 1 |
| `block_bulk_add` | `true` | Rule 2 |
| `require_worktree_base` | `true` | Rule 3 |
| `fail_mode` | `open` | When `git`/`jq` is missing: `open` allows, `closed` blocks |

## Requirements

`git` and `jq` on `PATH`. If either is missing the hook follows `fail_mode`
(default `open`, i.e. it stays out of the way).
