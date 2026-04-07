# secret-scanner

A Claude Code skill that scans staged git changes for leaked secrets before committing.

## Problem

API keys, tokens, and credentials accidentally committed to git are difficult to fully remove and can lead to security incidents.

## Solution

This skill scans staged diffs (or all tracked files) against a set of regex patterns for common secret formats. It can also be installed as a git pre-commit hook for automatic enforcement.

## Install

```bash
cp -r secret-scanner ~/.claude/skills/secret-scanner
```

## Usage

```bash
# Scan staged changes (default)
bash scan.sh

# Scan staged changes in a specific repo
bash scan.sh --path /path/to/repo

# Scan all tracked files
bash scan.sh --all

# Install as a git pre-commit hook
bash install-hook.sh --path /path/to/repo
```

Detected patterns include JWT tokens, GitHub PATs, Anthropic keys, AWS access keys, Azure DevOps PATs, Datadog keys, private keys, connection strings, and generic `password=`/`secret=`/`token=` assignments with real values.

The scanner ignores `.env` files, comment lines, and placeholder values (`YOUR_TOKEN`, `CHANGEME`, `TODO`, etc.).

## How it works

The `scan.sh` script collects staged files (or all tracked files with `--all`) and checks each line against regex patterns for known secret formats. Matches are reported to stderr with the file, line number, and pattern type. Exit code 0 means clean; exit code 1 means secrets were found. The `install-hook.sh` script appends `scan.sh --staged` to a repo's `.git/hooks/pre-commit` file.
