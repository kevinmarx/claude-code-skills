---
name: secret-scanner
version: 1.0.0
description: Pre-commit secret scanner that detects API keys, tokens, and credentials in staged changes. Use when committing code or as an installed git hook.
---

# Secret Scanner

Scans git staged content (or all tracked files) for leaked secrets before they get committed. Catches JWT tokens, API keys, private keys, passwords, connection strings, and more.

## When to Use

- Before committing code (automatically if installed as a hook)
- When reviewing staged changes for accidental secret leaks
- As a CI gate or manual audit of a repository

## Usage

### Scan staged changes (default)

```bash
bash /Users/kemarx/workspace/km/claude-code-skills/secret-scanner/scan.sh
```

### Scan staged changes in a specific repo

```bash
bash /Users/kemarx/workspace/km/claude-code-skills/secret-scanner/scan.sh --path /path/to/repo
```

### Scan all tracked files

```bash
bash /Users/kemarx/workspace/km/claude-code-skills/secret-scanner/scan.sh --all
```

### Install as a git pre-commit hook

```bash
bash /Users/kemarx/workspace/km/claude-code-skills/secret-scanner/install-hook.sh --path /path/to/repo
```

## Patterns Detected

| Pattern | Example |
|---|---|
| JWT tokens | `eyJhbGciOiJIUzI1NiIs...` |
| GitHub PATs | `ghp_xxxxxxxxxxxxxxxxxxxx` |
| Anthropic keys | `sk-ant-api03-...` |
| Generic sk- keys | `sk-xxxxxxxxxxxxxxxxxxxxxxxx` |
| AWS access keys | `AKIA...` |
| Azure DevOps PATs | `_password=base64string` or `_authToken=base64string` |
| Datadog keys | `DD_API_KEY=abcdef0123456789...` (32-char hex) |
| Private keys | `-----BEGIN RSA PRIVATE KEY-----` |
| Connection strings | `password=actualvalue` in connection strings |
| Generic secrets | `password=`, `secret=`, `token=` with real values |

## Ignored Content

- `.env` and `.secrets` files (expected to contain secrets)
- Comment lines (starting with `#`)
- Placeholder values (`YOUR_TOKEN`, `CHANGEME`, `PLACEHOLDER`, `xxx`, `TODO`, etc.)

## Exit Codes

- `0` — No secrets found
- `1` — Secrets detected (details printed to stderr)
