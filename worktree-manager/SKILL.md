---
name: worktree-manager
version: 1.0.0
description: Manage git worktrees with branch naming conventions (users/kemarx/*). Use when starting new work, listing worktrees, or cleaning up stale ones.
---

# worktree-manager

Manage git worktrees using the `users/kemarx/*` branch naming convention.

## When to use

- Starting new work on a feature, bugfix, or experiment
- Listing existing worktrees for the current repo
- Cleaning up worktrees whose branches have been merged or deleted
- Switching to an existing worktree

## Usage

```bash
bash ~/.claude/skills/worktree-manager/worktree.sh <subcommand> [args]
```

Must be run from within a git repository.

## Subcommands

### `new <name> [--base <branch>]`

Create a new worktree as a sibling directory to the current repo.

- Worktree path: `../<repo-name>-<name>`
- Branch: `users/kemarx/<name>`
- Base branch defaults to `main` or `master` (auto-detected)
- Fetches latest from remote before creating

```bash
# From /Users/kemarx/workspace/mai/groupme-ios
bash worktree.sh new fix-auth
# Creates: /Users/kemarx/workspace/mai/groupme-ios-fix-auth
# Branch: users/kemarx/fix-auth

bash worktree.sh new experiment --base develop
# Creates worktree based off develop instead of main
```

### `list`

List all worktrees for the current repo with branch and status.

```bash
bash worktree.sh list
```

### `clean [--force]`

Remove worktrees whose branches have been merged or deleted on remote.

```bash
bash worktree.sh clean          # interactive confirmation
bash worktree.sh clean --force  # skip confirmation
```

### `switch <name>`

Print the path to an existing worktree matching the name (partial match supported). Useful for `cd`-ing into a worktree.

```bash
bash worktree.sh switch fix-auth
# Prints: /Users/kemarx/workspace/mai/groupme-ios-fix-auth
```

## Linear ticket integration

When the user provides a Linear ticket ID (e.g., `GRO-123`) instead of a plain branch name:

1. Fetch the ticket details using `mcp__plugin_linear-mcp_linear-server__get_issue` with the ticket ID
2. Extract the ticket title and slugify it (lowercase, hyphens, max 50 chars)
3. Use the result as the branch name: `users/kemarx/<ticket-id>-<slugified-title>`
4. Example: ticket `GRO-456` titled "Fix push notification badge count" → branch `users/kemarx/gro-456-fix-push-notification-badge-count`

### Usage with Linear tickets:
```bash
# Claude should detect the ticket ID pattern and fetch from Linear
bash worktree.sh new GRO-123
```

When Claude detects a Linear ticket pattern (letters followed by a dash and numbers), it should:
1. Call the Linear MCP to get the issue title
2. Pass the slugified result to `worktree.sh new <slugified-name>`
3. After creating the worktree, update the Linear ticket with a comment noting the branch name

## ADO work item integration

Similarly, when given an ADO work item ID (numeric, e.g., `12345`):
1. Fetch via `mcp__plugin_azure-devops-mcp_azure-devops-mcp__wit_get_work_item`
2. Slugify the title
3. Create branch: `users/kemarx/<id>-<slugified-title>`
