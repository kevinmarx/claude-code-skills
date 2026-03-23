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
bash /Users/kemarx/workspace/km/claude-code-skills/token-rotator/check.sh

# Only show problems
bash /Users/kemarx/workspace/km/claude-code-skills/token-rotator/check.sh --quiet

# Machine-readable JSON output
bash /Users/kemarx/workspace/km/claude-code-skills/token-rotator/check.sh --json

# Combine flags
bash /Users/kemarx/workspace/km/claude-code-skills/token-rotator/check.sh --json --quiet
```

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

## Configuration

Edit `tokens.conf` in the same directory to add/remove tokens to monitor. Format:

```
# name | validation_source | validation_method
```

## Exit Codes

- `0` — All tokens valid
- `1` — One or more tokens expired or invalid
- `2` — One or more tokens expiring soon (< 7 days)
