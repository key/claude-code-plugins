# claude-code-plugins

key's personal Claude Code plugin marketplace.

## Plugins

| Name | Description |
|---|---|
| [`the-space-memory`](plugins/the-space-memory) | Cross-workspace knowledge search engine with hybrid FTS5 + vector search. Requires the `tsm` CLI to be installed separately. |
| [`current-datetime`](plugins/current-datetime) | Inject current datetime (system TZ) into UserPromptSubmit context. |
| [`statusline`](plugins/statusline) | Two-line Claude Code statusline (env, host, branch, model, context %, rate-limit). |
| [`lint-markdown`](plugins/lint-markdown) | Auto-format and lint Markdown files with rumdl on edit (PostToolUse). Requires `rumdl`. |
| [`lint-shell`](plugins/lint-shell) | Lint shell scripts with shellcheck on edit (PostToolUse). Requires `shellcheck`. |
| [`lint-yaml`](plugins/lint-yaml) | Lint YAML files with yamllint on edit (PostToolUse). Requires `yamllint`. |
| [`lint-python`](plugins/lint-python) | Auto-format and lint Python files with ruff on edit (PostToolUse). Requires `ruff`. |
| [`lint-toml`](plugins/lint-toml) | Auto-format and lint TOML files with taplo on edit (PostToolUse). Requires `taplo`. |
| [`secret-scan`](plugins/secret-scan) | Block secrets before they reach the LLM: scan prompts/files with gitleaks and Bash commands for risky patterns. Requires `gitleaks`. |

## Install

Add this repo as a marketplace from GitHub, then install the plugins you want.
Installing from GitHub keeps plugins easy to update (`/plugin marketplace update`)
and lets Claude Code pull the latest releases automatically.

In Claude Code, run:

```text
/plugin marketplace add https://github.com/key/claude-code-plugins.git
```

Then install a plugin (repeat per plugin you want):

```text
/plugin install the-space-memory@key-claude-code-plugins
```

Or browse and toggle plugins interactively:

```text
/plugin
```

To pull updates later:

```text
/plugin marketplace update key-claude-code-plugins
```

### Local development

To load a single plugin straight from a local checkout:

```bash
claude --plugin-dir /path/to/claude-code-plugins/plugins/<plugin-name>
```

## License

MIT. See [LICENSE](LICENSE). See individual plugins for upstream attribution.
