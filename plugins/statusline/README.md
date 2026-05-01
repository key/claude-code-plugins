# statusline

Two-line statusline for Claude Code. Shows execution environment,
host, working directory, git branch, model, context window usage,
and 5h / 7d rate-limit consumption — each as a fine-grained gradient
bar.

```text
📦 DevContainer | 🏠 vscode@d597:workspaces/the-space-memory | 🌿 main
🤖 Claude Sonnet 4.6 | 🧠 ctx ███████░░░ 72%
              | ⏱️ 5h ████░░░░░░ 41% | 📅 7d ██░░░░░░░░ 23%
```

(One actual line — wrapped here for readability.)

## Install

Claude Code plugins cannot ship `statusLine` configuration directly
(the manifest only covers commands, agents, skills, hooks, and MCP
servers). The script must be wired in from your own settings file.

The simplest pattern is to copy the script into your project and
reference it via `$CLAUDE_PROJECT_DIR`:

```bash
mkdir -p .claude/scripts
cp "${CLAUDE_PLUGIN_ROOT:-.}/scripts/statusline.sh" .claude/scripts/
chmod +x .claude/scripts/statusline.sh
```

Then add to `.claude/settings.json` (or your user-level
`~/.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/statusline.sh\""
  }
}
```

Reload Claude Code (`/reload-plugins` or restart) and the statusline
appears at the bottom of the session.

## What it shows

## Line 1

| Segment | Source |
|---|---|
| `📦 <env>` | `Sandbox` if `SANDBOX_RUNTIME=1` / `CLAUDE_CODE_BUBBLEWRAP=1`; `DevContainer` if `/.dockerenv` exists or `REMOTE_CONTAINERS` is set; otherwise omitted |
| `🏠 user@host:dir` | `whoami` + `hostname -s` + last two `cwd` segments |
| `🌿 <branch>` | `git -C <cwd> branch --show-current`; omitted outside a repo |

## Line 2

| Segment | Source |
|---|---|
| `🤖 <model>` | `model.display_name` from the JSON Claude Code pipes to the script |
| `🧠 ctx <bar> <pct>%` | `context_window.used_percentage` |
| `⏱️ 5h <bar> <pct>%` | `rate_limits.five_hour.used_percentage` |
| `📅 7d <bar> <pct>%` | `rate_limits.seven_day.used_percentage` |

The bars use 1/8-block characters (`▏▎▍▌▋▊▉█`) for sub-cell
resolution and recolour green → yellow → red as the percentage
crosses 50% and 80%.

## Dependencies

- `bash`
- `jq` (the script silently exits if `jq` is missing, so it never
  breaks Claude Code start-up)
- `git` (optional — branch segment is skipped outside a repo)

## License

MIT.
