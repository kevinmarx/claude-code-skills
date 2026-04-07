# gh-account-switcher

A Claude Code skill that auto-switches GitHub CLI accounts based on workspace directory.

## Problem

Working across multiple GitHub orgs (personal and work) means the wrong `gh` account is often active, causing PRs and API calls to fail silently or target the wrong org.

## Solution

This skill maps workspace directories to GitHub accounts and switches `gh auth` before any GitHub CLI operation. Claude runs it proactively whenever the working directory changes.

## Install

```bash
cp -r gh-account-switcher ~/.claude/skills/gh-account-switcher
```

## Usage

```bash
# Auto-switch based on current directory
bash switch.sh

# Switch for a specific path
bash switch.sh --path /Users/kemarx/workspace/mai/some-repo

# Check current vs expected account without switching
bash switch.sh --check

# Minimal output
bash switch.sh --quiet
```

Account mappings are defined in `accounts.conf`:

```
/Users/kemarx/workspace/mai | kemarx_microsoft
/Users/kemarx/workspace/km  | kevinmarx
/Users/kemarx/workspace/gm  | kevinmarx
```

## How it works

The `switch.sh` script reads `accounts.conf` to find the expected GitHub account for the current (or specified) directory path. It compares that against the active `gh auth` account and runs `gh auth switch --user` if they differ. Exit code 0 means the correct account is active; exit code 1 means no mapping was found or the switch failed.
