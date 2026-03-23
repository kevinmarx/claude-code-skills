# ticket-bridge

A Claude Code skill that bridges ticket systems (Linear, Azure DevOps) with your git workflow. Detects ticket references from branches and commits, generates PR descriptions with linked tickets, and orchestrates full ticket-to-branch and PR-to-ticket flows.

## Problem

Working across Linear and Azure DevOps means constant context switching: copy ticket IDs, manually format PR descriptions, remember to link PRs back to tickets, update ticket status. It's tedious and easy to forget steps.

## Solution

This skill gives Claude a script to detect ticket references and format PR links, plus orchestration instructions for the full lifecycle: start work from a ticket (fetch, branch, update status) and create PRs that link back (detect refs, generate body, post PR URL to tickets).

Ticket detection supports both systems:
- Linear: `GRO-123`, `MAI-456` (any `[A-Z]+-\d+` pattern)
- Azure DevOps: `AB#12345` or `#12345`

## Install

1. Copy the skill into your Claude Code skills directory:

```bash
cp -r ticket-bridge ~/.claude/skills/ticket-bridge
```

2. Ensure `jq` is installed:

```bash
# macOS
brew install jq

# Linux
apt install jq
```

3. (Optional) Set up repo-level config so ticket URLs are fully linked:

```bash
bash ~/.claude/skills/ticket-bridge/bridge.sh config --repo /path/to/repo \
  --set --linear-team groupme --ado-project GroupMe --ado-org nickelgroup
```

This writes to `.claude/settings.local.json` in the target repo.

## How it works

The `bridge.sh` script has three subcommands:

- **detect** parses the current branch name and last 5 commit messages for ticket ID patterns, deduplicates them, and outputs a JSON array with the ticket type and ID.

- **format-pr** takes a comma-separated list of ticket IDs and generates a markdown section with linked ticket references. It reads `.claude/settings.local.json` for org/team/project names to build full URLs; falls back to plain IDs if config is missing.

- **config** reads or writes the `ticketBridge` key in `.claude/settings.local.json`, storing the Linear team slug, ADO org, and ADO project for URL generation.

The `SKILL.md` instructs Claude on the full orchestration: when starting from a ticket, it fetches details via MCP, creates a branch with worktree-manager, updates ticket status, and comments the branch name. When creating a PR, it detects refs, fetches context, generates the PR body, creates the PR with `gh`, and links each ticket back to the PR.
