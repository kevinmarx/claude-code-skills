---
name: session-handoff
version: 1.0.0
description: Save and restore session context between Claude Code sessions. Captures branch, summary, in-flight files, and recent commits so a new session can pick up where the last one left off.
---

# session-handoff

Persist working context at the end of a session and restore it at the start of the next one.

## When to Use

**Call this proactively:**

- **End of session** -- before the user stops working, save a handoff.
- **Start of session** -- when a session begins, check for a recent handoff.
- **On explicit request** -- when the user asks to save or restore context.

## End-of-Session Workflow

1. Summarize the work done in the session (what changed, what's left, any blockers).
2. Save the handoff:

```bash
bash ~/.claude/skills/session-handoff/handoff.sh save --repo /Users/kemarx/workspace/project --summary "Implemented retry logic for API client, tests passing, still need to wire up config flags"
```

3. Store any durable insights (patterns learned, architectural decisions, gotchas) to local-memory MCP using the `remember` tool with category `session-insight`. These survive handoff cleanup and are useful across sessions.

**Key distinction:** Handoff files are ephemeral short-term context (branch, dirty files, recent work). Local-memory entries are permanent insights that stay useful long after the session details expire.

## Start-of-Session Workflow

1. Load the most recent handoff:

```bash
bash ~/.claude/skills/session-handoff/handoff.sh load --repo /Users/kemarx/workspace/project
```

2. Check local-memory MCP for repo-level insights using the `recall` tool with a query for the repo name.
3. If a handoff was found, give a brief 2-3 sentence recap of where things stand: what was done, what branch is active, and what's in flight.

## Other Commands

List recent handoffs across all repos:

```bash
bash ~/.claude/skills/session-handoff/handoff.sh list --limit 5
```

Clean up old handoffs:

```bash
bash ~/.claude/skills/session-handoff/handoff.sh clean --days 14
```
