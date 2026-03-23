---
name: token-rotator
version: 1.0.0
description: Check token expiry and health across services (GitHub, Azure DevOps, Anthropic, Datadog, Braintrust). Use to audit credential freshness or when auth failures occur.
---

# Token Rotator

Checks token expiry and health across multiple services. Reports which tokens need rotation.

## When to Use

- When auth failures occur with any integrated service
- Periodic credential freshness audit
- Before starting work that depends on multiple services
- After machine restarts or credential changes
- When MCP plugins fail with auth errors

## Usage

```bash
# Full health check (table output)
bash ~/.claude/skills/token-rotator/check.sh

# Only show problems
bash ~/.claude/skills/token-rotator/check.sh --quiet

# Machine-readable JSON output
bash ~/.claude/skills/token-rotator/check.sh --json

# Combine flags
bash ~/.claude/skills/token-rotator/check.sh --json --quiet
```

## MCP-based service checks

In addition to the shell-based checks, use the following MCP tools to validate service connectivity:

### Azure DevOps
Call `mcp__plugin_azure-devops-mcp_azure-devops-mcp__core_list_projects` with no arguments.
- If it returns projects, ADO auth is working.
- If it errors, the ADO PAT or MCP config is broken.

### Linear
Call `mcp__plugin_linear-mcp_linear-server__list_teams` with no arguments.
- If it returns teams, Linear auth is working.
- If it errors, the Linear API key or MCP config is broken.

### When running a full token audit:
1. Run `check.sh` for env-var and CLI-based tokens
2. Call the ADO MCP tool to verify ADO connectivity
3. Call the Linear MCP tool to verify Linear connectivity
4. Report all results together

## What It Checks

| Service | Method | What's Validated |
|---------|--------|-----------------|
| GitHub (kevinmarx) | `gh auth status` | Auth state, token expiry |
| GitHub (kemarx_microsoft) | `gh auth status` | Auth state, token expiry |
| Azure DevOps NPM | JWT decode from `~/.npmrc` | Token expiry timestamp |
| Anthropic | Env var presence | `ANTHROPIC_AUTH_TOKEN` is set |
| Datadog API | Env var presence | `DD_API_KEY` is set |
| Datadog App | Env var presence | `DD_APP_KEY` is set |
| Braintrust | Env var presence | `BRAINTRUST_API_KEY` is set |
| Azure DevOps MCP | MCP tool call | ADO connectivity via MCP |
| Linear MCP | MCP tool call | Linear connectivity via MCP |

## Configuration

Edit `tokens.conf` in the same directory to add/remove tokens to monitor. Format:

```
# name | validation_source | validation_method
```

## Exit Codes

- `0` — All tokens valid
- `1` — One or more tokens expired or invalid
- `2` — One or more tokens expiring soon (< 7 days)
