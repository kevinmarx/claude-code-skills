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
bash ~/.claude/skills/gh-account-switcher/switch.sh

# Switch for a specific path
bash ~/.claude/skills/gh-account-switcher/switch.sh --path /Users/kemarx/workspace/mai/some-repo

# Check which account should be active (no switching)
bash ~/.claude/skills/gh-account-switcher/switch.sh --check

# Quiet mode (single line, no decoration)
bash ~/.claude/skills/gh-account-switcher/switch.sh --quiet
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

## ADO org context

When switching GitHub accounts for `mai/*` repos, also be aware that:
- The Azure DevOps MCP server is configured for the Microsoft org
- ADO operations (PRs, work items, pipelines) in `mai/*` repos go through this org
- No switching is needed for ADO — the MCP server handles it — but confirm connectivity by calling `mcp__plugin_azure-devops-mcp_azure-devops-mcp__core_list_projects` if ADO operations fail

## Linear context

Linear MCP is workspace-scoped (GroupMe team). Linear tickets can be created from any workspace directory — the `gh-account-switcher` does not affect Linear operations.
