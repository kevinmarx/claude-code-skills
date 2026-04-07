# token-rotator

A Claude Code skill that checks token expiry and health across GitHub, Azure DevOps, Anthropic, Datadog, and Braintrust.

## Problem

Tokens expire silently across multiple services, and the first sign is usually a cryptic auth failure in the middle of real work.

## Solution

This skill runs a single health check across all configured tokens and reports which are valid, expiring soon, or already expired. Claude can also verify MCP-based services (ADO, Linear) via tool calls.

## Install

```bash
cp -r token-rotator ~/.claude/skills/token-rotator
```

## Usage

```bash
# Full health check (table output)
bash check.sh

# Only show problems
bash check.sh --quiet

# Machine-readable JSON output
bash check.sh --json

# Combine flags
bash check.sh --json --quiet
```

## How it works

The `check.sh` script reads `tokens.conf` and runs the appropriate validation method for each entry: `gh auth status` for GitHub accounts, JWT decode for Azure DevOps NPM tokens (extracts the `exp` claim from `~/.npmrc`), env var presence checks for Anthropic/Datadog/Braintrust, and LiteLLM health endpoint probes. MCP-based services (ADO, Linear) are validated by Claude calling the respective MCP tools after the script runs. Exit code 0 means all tokens are valid, 1 means one or more are expired, and 2 means one or more are expiring within 7 days.
