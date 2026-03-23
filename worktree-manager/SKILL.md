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
bash /Users/kemarx/workspace/km/claude-code-skills/worktree-manager/worktree.sh <subcommand> [args]
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
