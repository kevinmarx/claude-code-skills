---
name: gh-account-switcher
version: 1.0.0
description: Auto-switch GitHub CLI accounts based on workspace directory. Use proactively before any gh commands, or when switching between repos in different orgs.
---

# gh-account-switcher

Automatically switches the active GitHub CLI (`gh`) account based on which workspace directory you're in.

## When to Use

- **Proactively** before running any `gh` commands (pr create, issue list, repo clone, etc.)
- When switching between repos in different orgs (e.g., from `mai/` to `km/`)
- After `cd`-ing into a different workspace area

## Account Mapping

| Directory Pattern | GitHub Account |
|---|---|
| `/Users/kemarx/workspace/mai/*` | `kemarx_microsoft` |
| `/Users/kemarx/workspace/km/*` | `kevinmarx` |
| `/Users/kemarx/workspace/gm/*` | `kevinmarx` |

Mappings are configured in `accounts.conf`.

## Usage

```bash
# Auto-switch based on current directory
bash /Users/kemarx/workspace/km/claude-code-skills/gh-account-switcher/switch.sh

# Switch for a specific path
bash /Users/kemarx/workspace/km/claude-code-skills/gh-account-switcher/switch.sh --path /Users/kemarx/workspace/mai/some-repo

# Check which account should be active (no switching)
bash /Users/kemarx/workspace/km/claude-code-skills/gh-account-switcher/switch.sh --check

# Quiet mode (single line, no decoration)
bash /Users/kemarx/workspace/km/claude-code-skills/gh-account-switcher/switch.sh --quiet
```

## Flags

| Flag | Description |
|---|---|
| `--path <dir>` | Use this directory instead of cwd |
| `--check` | Report current vs expected account without switching |
| `--quiet` | Minimal output (one line) |

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Already on correct account, or switch succeeded |
| `1` | No mapping found for directory, or switch failed |
