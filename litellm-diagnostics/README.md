# litellm-diagnostics

A Claude Code skill that diagnoses the local LiteLLM proxy at `localhost:4000`.

## Problem

When Claude Code hits auth errors, timeouts, or model-not-found failures, it's unclear whether the issue is the proxy, the upstream provider, or a misconfigured env var.

## Solution

This skill provides subcommands to check proxy health, list available models, tail logs, send test completions, and restart the process, all from a single script.

## Install

```bash
cp -r litellm-diagnostics ~/.claude/skills/litellm-diagnostics
```

## Usage

```bash
# Quick health check (port, process, env vars)
bash diag.sh status

# List all models available through the proxy
bash diag.sh models

# Tail recent proxy logs
bash diag.sh logs
bash diag.sh logs --lines 100

# Send a test completion request
bash diag.sh test
bash diag.sh test --model claude-sonnet-4-20250514

# Stop the proxy and print restart instructions
bash diag.sh restart
```

## How it works

The `diag.sh` script uses `curl` to hit the proxy's `/health` and `/v1/models` endpoints, `lsof` to identify the process on port 4000, and `docker` commands to detect containerized instances. The `test` subcommand sends a minimal chat completion and reports latency and token usage. The `logs` subcommand checks docker containers first, then falls back to common log file paths and `lsof`-based discovery. Requires `curl`, `jq`, and `lsof`.
