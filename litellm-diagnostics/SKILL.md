---
name: litellm-diagnostics
version: 1.0.0
description: Diagnose local LiteLLM proxy health, check endpoints, tail logs, and report status. Use when Claude Code has auth errors, slow responses, or proxy issues.
---

# LiteLLM diagnostics

Diagnose and troubleshoot the local LiteLLM proxy running at `http://localhost:4000`.

## When to use

- Claude Code is getting auth errors or 401/403 responses
- Responses are slow or timing out
- You need to verify which models are available through the proxy
- The proxy seems down or unresponsive
- After restarting the proxy, to confirm it's healthy

## Usage

```bash
bash /Users/kemarx/workspace/km/claude-code-skills/litellm-diagnostics/diag.sh <subcommand> [options]
```

## Subcommands

### `status`

Quick health check of the proxy. Reports whether it's running, response time, what process owns port 4000, and whether required env vars are set.

```bash
bash diag.sh status
```

### `models`

List all models available through the proxy.

```bash
bash diag.sh models
```

### `logs [--lines N]`

Tail recent proxy logs. Defaults to 50 lines. Checks docker containers first, then falls back to process stdout discovery.

```bash
bash diag.sh logs
bash diag.sh logs --lines 100
```

### `test [--model <model>]`

Send a minimal chat completion request to verify end-to-end functionality. Reports success/failure, latency, and token usage.

```bash
bash diag.sh test
bash diag.sh test --model claude-sonnet-4-20250514
```

### `restart`

Find and stop the existing litellm process (or docker container), then print instructions for restarting.

```bash
bash diag.sh restart
```

## Common troubleshooting

| Symptom | Check |
|---|---|
| `connection refused` on port 4000 | `diag.sh status` — proxy probably not running |
| 401/403 from Claude Code | `diag.sh status` — check env vars, then `diag.sh test` |
| Model not found errors | `diag.sh models` — verify the model ID matches what you're requesting |
| Slow responses | `diag.sh test` — check response time; `diag.sh logs` for upstream errors |
| Proxy crashed | `diag.sh logs --lines 200` to find the error, then `diag.sh restart` |

## Dependencies

The script uses standard tools: `curl`, `jq`, `lsof`. It will warn if any are missing.
