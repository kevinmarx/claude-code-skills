# Ship It v2

Autonomous PR shepherd — drives a pull request from "has review comments" to "merged."

## Usage

```
/ship-it <PR_NUMBER>
/ship-it 456 --max-iterations 30
/ship-it                          # auto-detects PR from current branch
```

## What it does

1. **Fetches all review comments** from 3 sources (PR comments, review bodies, inline review comments) using cursor-based filtering
2. **Triages every finding** — each structured finding (F1, Q2, etc.) gets its own verdict: IMPLEMENT, REJECT, or BLOCKED
3. **Fixes code** and replies to every comment with what was done and why
4. **Monitors CI** via ADO MCP — reads failure logs, fixes code issues, requeues flaky/infrastructure failures
5. **Resolves merge conflicts** via rebase (new in v2 — v1 aborted on conflicts)
6. **Merges** with `--admin --squash --delete-branch` when all gates pass

## Architecture

```
Main Context (SKILL.md) — pre-flight + iteration loop manager
  └─ for each iteration (fresh context):
       └─ Lead Agent (loop-agent.md) — ONE cycle, reads checkpoint, acts, writes checkpoint, exits
            ├─ Comment Triage Agent — 3-source fetch + cursor filter + triage + fix + reply
            ├─ CI Fix Agent — ADO MCP log reading + categorized fix/requeue
            └─ Conflict Resolution Agent — rebase + verify + force-with-lease push
```

## Checkpoint

State is persisted to `.ship-it/pr-<N>/checkpoint.json` with cursor-based tracking (no growing arrays). This enables:
- **Resumability**: Kill mid-run, re-invoke, picks up from cursor
- **Bounded state**: O(1) checkpoint size regardless of comment volume

## Merge gates

All five must pass before merge:
1. HEAD SHA matches PR head on GitHub
2. Both ADO pipelines (446647, 447965) show SUCCESS or NEUTRAL
3. Fresh comment re-check (re-fetch all 3 sources)
4. PR is OPEN and mergeable
5. At least 1 approval exists

## CI fix budget

5 attempts per `category::component::stage` key. Categories:
- **Code issues** (ruff, mypy, pytest, build): fix the code, verify, push
- **Infrastructure/flaky**: requeue the pipeline via ADO MCP

## Comment verdicts

| Verdict | When | Action |
|---------|------|--------|
| IMPLEMENT | Valid finding | Fix, verify, reply "Fixed — description" |
| REJECT | Wrong/stale/disagree with evidence | Reply with reasoning |
| BLOCKED | Fix causes regressions | Revert, reply, request guidance |

## Terminal conditions

- PR not found / closed / already merged
- Conflicts unresolvable (outside PR scope)
- CI failure 5x same category::component::stage
- Max iterations exceeded (default 30)
- `--admin` merge fails (permissions)

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Thin orchestrator — pre-flight + lead agent dispatch |
| `references/loop-agent.md` | Core agentic loop with all phases |
| `references/comment-triage-agent.md` | 3-source comment fetch + cursor filter + triage |
| `references/ci-fix-agent.md` | ADO MCP log reading + categorized fix/requeue |
| `references/conflict-resolution-agent.md` | Rebase-based conflict resolution |
