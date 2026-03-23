# worktree-manager

A Claude Code skill that manages git worktrees with `users/kemarx/*` branch naming conventions.

## Problem

Starting new work requires creating a worktree, picking a sibling directory path, naming the branch with the right prefix, and basing it off the correct upstream branch. Cleaning up merged worktrees is equally tedious.

## Solution

This skill wraps git worktree operations into subcommands that enforce naming conventions, auto-detect the default branch, and handle cleanup of stale worktrees.

## Install

```bash
cp -r worktree-manager ~/.claude/skills/worktree-manager
```

## Usage

```bash
# Create a new worktree (branch: users/kemarx/fix-auth)
bash worktree.sh new fix-auth

# Create from a different base branch
bash worktree.sh new experiment --base develop

# List all worktrees with dirty/clean status
bash worktree.sh list

# Clean up worktrees whose branches are merged or deleted
bash worktree.sh clean
bash worktree.sh clean --force

# Find and print the path to an existing worktree
bash worktree.sh switch fix-auth
```

When given a Linear ticket ID (e.g., `GRO-123`) or ADO work item ID, Claude fetches the title via MCP, slugifies it, and uses it as the branch name.

## How it works

The `worktree.sh` script creates worktrees as sibling directories (`../<repo>-<name>`) with branches under `users/kemarx/`. It fetches from origin before creating, auto-detects `main` or `master`, and supports partial-match switching. The `clean` subcommand prunes worktrees whose branches have been merged into the default branch or deleted on remote.
