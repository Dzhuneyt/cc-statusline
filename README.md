# cc-statusline

A two-line ANSI statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Shows model, context window, rate limits, cost, git status, and session stats — updated on every render cycle.

## What it shows

**Line 1:** model name | context usage bar | working directory | worktree | git branch + diff stats | lines changed | cost | duration

**Line 2:** 5-hour rate limit | 7-day rate limit | token counts (in/out)

## Requirements

- bash
- [jq](https://jqlang.org/)
- git (for git status display)

## Installation

```bash
git clone https://github.com/Dzhuneyt/cc-statusline.git ~/cc-statusline
chmod +x ~/cc-statusline/statusline.sh
```

Add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/cc-statusline/statusline.sh",
    "padding": 1
  }
}
```

Restart Claude Code. The statusline should appear below the prompt.

## Configuration

Everything is shown by default. Control visibility and tuning via environment variables.

Set them in your shell profile, or in Claude Code's settings under `"env"`:

```json
{
  "env": {
    "CS_HIDE_7D_USAGE": "1"
  }
}
```

Or prefix the command directly:

```json
{
  "statusLine": {
    "type": "command",
    "command": "CS_HIDE_7D_USAGE=1 ~/cc-statusline/statusline.sh"
  }
}
```

### Visibility toggles

Set any of these to a non-empty value (e.g. `1`) to hide that section.

| Variable | Hides |
|---|---|
| `CS_HIDE_MODEL` | Model name |
| `CS_HIDE_CONTEXT` | Context window bar |
| `CS_HIDE_DIR` | Working directory |
| `CS_HIDE_GIT` | Git branch and diff stats |
| `CS_HIDE_LINES` | Session lines added/removed |
| `CS_HIDE_5H_USAGE` | 5-hour rate limit |
| `CS_HIDE_7D_USAGE` | 7-day rate limit |
| `CS_HIDE_TOKENS` | Token counts |
| `CS_HIDE_WORKTREE` | Worktree indicator |
| `CS_HIDE_COST` | Session cost |
| `CS_HIDE_DURATION` | Session duration |

### Tuning

| Variable | Default | Description |
|---|---|---|
| `CS_CTX_BAR_WIDTH` | `4` | Context bar width (characters) |
| `CS_RL_BAR_WIDTH` | `4` | Rate limit bar width (characters) |
| `CS_CTX_WARN_PCT` | `50` | Context % for yellow warning |
| `CS_CTX_CRIT_PCT` | `75` | Context % for red critical |
| `CS_RL_WARN_PCT` | `70` | Rate limit % for yellow |
| `CS_RL_CRIT_PCT` | `90` | Rate limit % for red |
| `CS_RL_7D_SHOW_PCT` | `40` | Only show 7-day limit above this % |
| `CS_GIT_CACHE_TTL` | `5` | Git status cache TTL (seconds) |
| `CS_CACHE_DIR` | `/tmp` | Directory for git cache files |

## How it works

Claude Code pipes a JSON object to the script's stdin on every render cycle. The script parses all fields in a single `jq` call and outputs two ANSI-colored lines.

Git status is cached per-directory (keyed by MD5 of the working directory path) with a configurable TTL to avoid running git commands on every render.

## Tests

```bash
./tests.sh
```

## License

MIT
