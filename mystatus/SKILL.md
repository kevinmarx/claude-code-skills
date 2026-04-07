---
name: mystatus
version: 1.0.0
description: Morning dashboard showing Linear tickets and GitHub PRs scoped by organization. Invoke with `/mystatus <org>` to see what needs attention.
---

# mystatus

Aggregates Linear tickets and GitHub PRs into a single status view scoped by organization.

## When to Use

When the user runs `/mystatus <org>` (e.g., `/mystatus mai`, `/mystatus gm`).

## Setup

This skill requires a config file at `~/.claude/skills/mystatus/config.json`. If it doesn't exist, tell the user to create one. See the README for the config format.

## How to Execute

### 1. Load config

Read `~/.claude/skills/mystatus/config.json`. Parse the `orgs` object to find the requested org. If no org argument is given, list the available orgs from the config and stop.

If the org isn't found in config, tell the user and list available orgs.

### 2. Linear — My open tickets

For each team in the org's `linearTeams` array, call the Linear MCP tool `list_issues` with:
- `assignee`: `"me"`
- `team`: the team key
- Do NOT pass a `state` filter — Linear's state types (triage, unstarted, started) don't map cleanly and you'll miss tickets

From the results, **exclude** any ticket where status is "Done", "Canceled", "Cancelled", or "Duplicate". Everything else (Triage, Todo, In Progress, In Review, etc.) should be shown.

Sort by priority (Urgent first, then High, Medium, Low, None). Display each ticket as a markdown link using the `url` field from the response:
```
- [IDENT](url) [Status] Title — Priority
```

### 3. Linear — Unassigned tickets

For each team in the org's `linearTeams` array, call `list_issues` with:
- `team`: the team key
- `state`: `"unstarted"`

From the results, **filter to only tickets where assignee is null/empty** (the MCP tool doesn't reliably support null assignee filtering, so you must filter client-side).

Display the same linked format. This shows backlog items needing an owner. Cap at 10 to keep the dashboard concise.

### 4. GitHub — PRs needing my review & my PRs needing action

Run the status script:
```bash
bash ~/.claude/skills/mystatus/status.sh --org <org>
```

The script reads config.json, switches the gh account, and outputs JSON for two sections:
- `prs_to_review`: PRs where I'm requested as a reviewer
- `my_prs`: My open PRs (with review decision and check status)

Format `prs_to_review` as markdown links using the `url` field:
```
- [owner/repo#number](url) — "title" by @author
```

Format `my_prs`, filtering to only PRs that need action (changes_requested or failing checks):
```
- [owner/repo#number](url) — "title" — Changes requested | Checks failing
```

If a section has no items, show the section header with "(0)" and a "Nothing here" message.

### 5. Output format

Use this structure:

```
## Morning Status — <ORG>

### My Linear Tickets (count)
...

### Unassigned Tickets (count)
...

### PRs Needing My Review (count)
...

### My PRs Needing Action (count)
...
```

Keep it concise. No extra commentary unless something looks wrong.
