# mystatus

A Claude Code skill that gives you a morning dashboard scoped by organization. Aggregates Linear tickets and GitHub PRs into a single status view.

## Problem

Starting your day means checking Linear for your tickets, then GitHub for PR reviews, across different orgs with different accounts. That's multiple tabs and context switches before you even start coding.

## Solution

Run `/mystatus mai` or `/mystatus gm` and get a single view of:
- Your open Linear tickets (grouped by team)
- Unassigned tickets that need an owner
- PRs requesting your review
- Your PRs that need action (changes requested, failing checks)

The skill handles GitHub account switching automatically.

## Install

1. Copy the skill into your Claude Code skills directory:

```bash
cp -r mystatus ~/.claude/skills/mystatus
```

2. Create your config file at `~/.claude/skills/mystatus/config.json`:

```json
{
  "orgs": {
    "myorg": {
      "linearTeams": ["TEAM1", "TEAM2"],
      "githubOwner": "my-github-org",
      "githubAccount": "my-gh-username",
      "workspacePath": "~/workspace/myorg"
    }
  },
  "linearUser": "my-linear-username"
}
```

Each org entry maps to:
- `linearTeams` — Linear team keys to query for tickets
- `githubOwner` — GitHub org/user to scope PR searches
- `githubAccount` — The `gh auth` account to switch to (for multi-account setups)
- `workspacePath` — Local workspace path (for reference)

3. Make sure you have `jq` and `gh` CLI installed.

## Usage

```
/mystatus mai     # Show MAI org status
/mystatus gm      # Show GroupMe org status
/mystatus         # List available orgs
```

## Adding a new org

Add another entry to the `orgs` object in your config.json. The key is what you pass to `/mystatus`.

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`) with accounts authenticated
- [jq](https://jqlang.github.io/jq/) for JSON parsing
- Linear MCP plugin configured in Claude Code
- Multiple `gh auth` accounts if you work across GitHub orgs

## How it works

- **Linear queries** go through Claude's Linear MCP tools directly — no account switching needed
- **GitHub queries** run through `status.sh`, which reads the config, switches the `gh` CLI account, and runs `gh search prs` commands
- The skill outputs a formatted dashboard with counts and actionable items
