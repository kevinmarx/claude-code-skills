# session-handoff

A Claude Code skill that saves and restores working context between sessions so you never lose track of where you left off.

## Problem

When you close a Claude Code session and start a new one later, all context is gone -- what branch you were on, what files were in flight, what you were working on. You have to manually re-explain the state of things every time.

## Solution

This skill tells Claude to proactively save a handoff file at the end of each session capturing the branch, a summary of work done, uncommitted files, and recent commits. When a new session starts, Claude loads the latest handoff and gives a brief recap.

Short-term session context lives in handoff files (`~/.claude/session-handoffs/`). Longer-lived insights (architectural decisions, gotchas, patterns) get stored in local-memory MCP so they persist indefinitely.

## Install

1. Copy the skill into your Claude Code skills directory:

```bash
cp -r session-handoff ~/.claude/skills/session-handoff
```

2. The script stores handoff files in `~/.claude/session-handoffs/`. The directory is created automatically on first use.

3. `jq` is recommended but not required. The script falls back to manual JSON construction if `jq` is not available.

That's it. Claude Code will automatically discover the skill and start using it.

## How it works

The `SKILL.md` file instructs Claude to run `handoff.sh save` at the end of sessions and `handoff.sh load` at the start. The save command captures the current git branch, uncommitted files, recent commit history, and a summary into a timestamped JSON file. The load command finds the most recent handoff for the repo and prints a human-readable recap with relative timestamps. A list command shows recent handoffs across all repos, and a clean command removes old files.
