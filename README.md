# cc-statusline

[![Tests](https://github.com/Dzhuneyt/cc-statusline/actions/workflows/tests.yml/badge.svg)](https://github.com/Dzhuneyt/cc-statusline/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A batteries-included statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with context usage, rate limits, git status, session cost, and token counts.

<img width="953" height="110" alt="image" src="https://github.com/user-attachments/assets/e1e750c9-8f4d-47bc-b98a-515b1de5ec38" />

## What it shows

**Line 1:**

| Section | Example | Notes |
|---|---|---|
| Model name | `Opus 4.6` | Parenthetical suffix stripped |
| Context usage | `█░░░░░░░░░ 8%` | 10-wide bar, green/yellow/red |
| Working directory | `~/projects/my-app` | `~` shorthand for `$HOME` |
| Worktree | `wt:feature-x` | Only shown if active |
| Git status | `main +60 -14 (git)` | Branch + staged/unstaged/untracked |
| Session lines | `+174 -27 (session)` | Cumulative lines changed by Claude |
| Cost | `$16.38` | Session spend |
| Duration | `5h39m` | Session uptime |

**Line 2:**

| Section | Example | Notes |
|---|---|---|
| 5h rate limit | `5h █░░░ 40%` | With time-till-reset |
| 7d rate limit | `7d ██░░ 60%` | Only shown above 40% usage |
| Tokens | `125.0k in/45.0k out` | Input/output token counts |

The `(git)` and `(session)` suffixes disambiguate the two sets of `+/-` numbers at a glance.

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

## Updating

```bash
cd ~/cc-statusline && git pull
```

No restart needed — the script is read fresh on every render cycle.

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

### Examples

**Minimal** — model + context only:

```json
{
  "env": {
    "CS_HIDE_DIR": "1",
    "CS_HIDE_GIT": "1",
    "CS_HIDE_LINES": "1",
    "CS_HIDE_COST": "1",
    "CS_HIDE_DURATION": "1",
    "CS_HIDE_5H_USAGE": "1",
    "CS_HIDE_7D_USAGE": "1",
    "CS_HIDE_TOKENS": "1",
    "CS_HIDE_WORKTREE": "1"
  }
}
```

**No rate limits** — hide both rate limit indicators:

```json
{
  "env": {
    "CS_HIDE_5H_USAGE": "1",
    "CS_HIDE_7D_USAGE": "1"
  }
}
```

**Wider context bar with earlier warnings:**

```json
{
  "env": {
    "CS_CTX_BAR_WIDTH": "20",
    "CS_CTX_WARN_PCT": "30",
    "CS_CTX_CRIT_PCT": "60"
  }
}
```

<details>
<summary><strong>Advanced configuration</strong></summary>

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
| `CS_CTX_BAR_WIDTH` | `10` | Context bar width (characters) |
| `CS_RL_BAR_WIDTH` | `4` | Rate limit bar width (characters) |
| `CS_CTX_WARN_PCT` | `50` | Context % for yellow warning |
| `CS_CTX_CRIT_PCT` | `75` | Context % for red critical |
| `CS_RL_WARN_PCT` | `70` | Rate limit % for yellow |
| `CS_RL_CRIT_PCT` | `90` | Rate limit % for red |
| `CS_RL_7D_SHOW_PCT` | `40` | Only show 7-day limit above this % |
| `CS_GIT_CACHE_TTL` | `5` | Git status cache TTL (seconds) |
| `CS_CACHE_DIR` | `/tmp` | Directory for git cache files |

</details>

## How it works

Claude Code pipes a JSON object to the script's stdin on every render cycle. The script parses all fields in a single `jq` call and outputs two ANSI-colored lines.

Git status is cached per-directory (keyed by MD5 of the working directory path) with a configurable TTL to avoid running git commands on every render.

## FAQ

**Does this slow down Claude Code?**
No. The script runs in under 50ms. Git status is cached per-directory with a 5-second TTL, so it doesn't shell out to git on every render.

**Does it work on Linux?**
Yes. The only dependency is `jq` and `git`. The script uses `md5sum` (Linux) with a fallback to `md5` (macOS) for cache keys.

**Why is the context bar empty at very low percentages?**
Each block represents 10%. The bar uses ceiling rounding, so any usage from 1-10% shows one filled block. Only exactly 0% shows a fully empty bar.

**Can I use this with Claude Code on VS Code or JetBrains?**
The `statusLine.command` setting works in the CLI. IDE extensions may not support custom statuslines — check the Claude Code docs for your IDE.

## Tests

```bash
./tests.sh
```

## Contributing

Issues and PRs are welcome — see the [issue tracker](https://github.com/Dzhuneyt/cc-statusline/issues).

## License

MIT
