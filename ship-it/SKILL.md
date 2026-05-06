---
name: ship-it
description: |
  Autonomous PR iteration loop: addresses review comments, waits for CI, iterates
  until green with no unresolved threads, then admin-merges with --squash --delete-branch.
  Takes an existing PR number as input. Designed for autonomous execution after
  /fix, /feature-dev, or /prod-triage-and-fix creates a PR.
  Uses an agent swarm — all iteration work is delegated to agents so main context stays clean.
---

# Ship It v2

```
        ~
   ___|_|___
  |  SHIP  |
  |   IT   |
   \______/
~~~~\____/~~~~~~~~~~~~~~~~~~~~
  ~~~  ~~~  ~~~  ~~~  ~~~  ~~~
```

Autonomous PR shepherd — drives a pull request from "open with comments" to "merged." Main context does pre-flight validation, then manages the iteration loop — dispatching a **fresh Lead Agent per iteration** so context never accumulates. Checkpoint cursors bridge the gap between iterations.

**Runs AUTONOMOUSLY. Only stop if genuinely blocked.**

## When to Use

- "ship it", "merge this PR", "land this PR"
- "address the review comments and merge"
- "iterate on PR #N until it's green"
- After `/fix`, `/feature-dev`, or `/prod-triage-and-fix` creates a PR

## When NOT to Use

- PR needs design-level rework (not just feedback fixes)
- PR targets a release branch — use manual merge

## Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `<number>` | (none) | PR number. Auto-detects from current branch if omitted. |
| `--max-iterations N` | 30 | Maximum loop iterations before aborting |

---

## State File I/O: Use Bash, Not create/edit

**CRITICAL**: All reads and writes to `.ship-it/pr-<N>/checkpoint.json` MUST use **Bash** (e.g., `cat`, `jq`, shell heredocs), NOT the create or edit tools. The create/edit tools render full diffs in the user's output, which pollutes the main context with noisy state updates every iteration.

This applies to the main context AND to all sub-agents.

---

## Pre-flight (Main Context)

Run these checks, then hand off to the Lead Agent. Abort with a clear error if any fail.

1. **Parse arguments**: Extract PR number from args. Extract `--max-iterations N` (default 30).
2. **Determine PR number**: from argument, or `gh pr view --json number -q .number`
3. **Validate PR state**:
   ```bash
   gh pr view <number> --json number,title,state,headRefName,baseRefName,mergeable
   ```
   Must be `OPEN`. If merged/closed, abort.
4. **Checkout PR branch**: `git fetch origin <headRefName> && git checkout <headRefName> && git pull`
5. **Get repo info**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   HOSTNAME=$(gh repo view --json url -q '.url' | sed 's|https://||;s|/.*||')
   HEAD_SHA=$(git rev-parse HEAD)
   ```
6. **Create workspace + checkpoint**:
   ```bash
   mkdir -p .ship-it/pr-<number>
   ```
   Write `.ship-it/pr-<number>/checkpoint.json` via Bash:
   ```json
   {
     "version": 2,
     "pr_number": <number>,
     "repo": "<owner/repo>",
     "branch": "<headRefName>",
     "base_branch": "<baseRefName>",
     "hostname": "<hostname>",
     "cursor": {
       "comments_since": "<current ISO timestamp>",
       "reviews_since": "<current ISO timestamp>",
       "last_seen_head_sha": "<HEAD_SHA>"
     },
     "ci_fix_attempts": {},
     "status": "in_progress",
     "iteration": 0,
     "max_iterations": <max_iterations>
   }
   ```
   **IMPORTANT for cursor initialization**: Set `comments_since` and `reviews_since` to `"1970-01-01T00:00:00Z"` so the first pass fetches ALL existing comments. After the first triage pass, the cursor advances to `max(all_timestamps_seen)`.

7. **Iteration loop** — main context manages this directly:
   ```
   while true:
     read checkpoint.json
     if status != "in_progress" → break (merged or aborted)
     if iteration >= max_iterations → set status "aborted", write checkpoint, break

     task(agent_type="general-purpose", prompt="
     You are the Ship It Lead Agent for PR #<number>.
     Read and follow references/loop-agent.md (relative to the ship-it skill directory).
     Checkpoint: .ship-it/pr-<number>/checkpoint.json
     Repo: <REPO> | Hostname: <HOSTNAME>
     Branch: <headRefName> → <baseRefName>
     Execute exactly ONE iteration, update the checkpoint, and exit.
     ")

     read checkpoint.json again
     if status == "merged" or status == "aborted" → break
     sleep 180  # 3 min — let CI run, let reviewers respond
   ```

   Each lead agent gets a **fresh context** — no accumulated state. The checkpoint cursor is the only bridge between iterations.

8. **Report result**: Read the final checkpoint and report the outcome to the user. Cleanup: `rm -rf .ship-it/pr-<number>`

---

## Architecture

```
Main Context (SKILL.md) — pre-flight + iteration loop manager
  └─ for each iteration (fresh context):
       └─ Lead Agent (loop-agent.md) — ONE cycle, reads checkpoint, acts, writes checkpoint, exits
            ├─ Comment Triage Agent (comment-triage-agent.md)
            ├─ CI Fix Agent (ci-fix-agent.md)
            └─ Conflict Resolution Agent (conflict-resolution-agent.md)
```

All reference docs are in the `references/` directory relative to this skill.

---

## Guardrails

- **Never force-push** to any branch (conflict resolution uses `--force-with-lease` only)
- **NEVER merge unless CI is green for the HEAD commit** — both required pipelines (446647, 447965) must show SUCCESS or NEUTRAL for the exact HEAD SHA
- **Requeue CI on infrastructure/flaky failures** via ADO MCP
- **Merge when all comments are addressed** — `CHANGES_REQUESTED` is not a blocker if every comment has been triaged
- **Never merge without a fresh comment re-check**
- **Never modify files outside the PR's diff scope**
- **Never delete or rewrite git history** (except rebase for conflict resolution)
- **Verify before push** — ruff + mypy + tests must pass before ANY push
- **Maximum iterations enforced** (default 30)
- **Every finding gets a reply** — no silent skips
- **Cursor-based state** — no growing arrays in checkpoint

## Error Handling

| Situation | Terminal? |
|-----------|-----------|
| PR not found / closed / already merged | Yes |
| Conflicts unresolvable (outside PR scope) | Yes |
| CI failure 5x same category | Yes |
| Max iterations exceeded | Yes |
| `--admin` merge fails (permissions) | Yes |
| CI pending / SHA mismatch / new comments at merge | No (wait + continue) |
| ADO MCP unavailable for requeue | No (log warning, wait) |
