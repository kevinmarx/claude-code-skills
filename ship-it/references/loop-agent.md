# Ship It — Lead Agent: Single Iteration

You are the Lead Agent for Ship It. You execute **exactly one iteration cycle**, then exit. The main context manages the loop and dispatches a fresh agent (you) for each iteration — this keeps context bounded.

Your job: read the checkpoint, run one sync/gather/route cycle, write the updated checkpoint, and exit.

## State File I/O

**CRITICAL**: All reads and writes to the checkpoint file MUST use **Bash** (`cat`, `jq`, shell heredocs), NOT the create or edit tools which pollute output with diffs.

---

## Iteration Flow

```
read checkpoint.json
if status != "in_progress" → exit immediately
increment iteration in memory

# Phase 1: Sync
git fetch + pull; if conflict → spawn conflict-resolution-agent
  if BLOCKED → set status "aborted", write checkpoint, exit

# Phase 2: Gather (parallel)
spawn 2 tasks in parallel:
  A) CI Status — inline (not worth a sub-agent)
  B) Comments — spawn comment-triage-agent

# Phase 3: Route
if triage agent pushed fixes → advance cursor, write checkpoint, exit
if CI failures exist → spawn ci-fix-agent, write checkpoint, exit
if CI pending → write checkpoint, exit
if CI green + no new comments → run merge gates (Step 4)

write checkpoint, exit
```

After you exit, the main context reads the checkpoint and decides whether to dispatch the next iteration (after a 3-min sleep) or report the final result.

---

## Phase 1: Sync

```bash
git fetch origin <branch>
git pull origin <branch>
```

If `git pull` fails with merge conflicts:
1. Spawn a conflict resolution agent:
   ```
   task(agent_type="general-purpose", prompt="
   You are resolving merge conflicts for PR #<N>.
   Read and follow the instructions in references/conflict-resolution-agent.md (relative to the ship-it skill directory).
   Checkpoint: .ship-it/pr-<N>/checkpoint.json
   Branch: <branch> | Base: <base_branch>
   ")
   ```
2. If the agent reports BLOCKED (conflicts outside PR scope or verification fails):
   - Set `status: "aborted"` in checkpoint
   - Output: "Merge conflicts could not be resolved automatically. Manual intervention required."
   - Break the loop

---

## Phase 2: Gather

Run these **in parallel** (two Task tool calls in a single message):

### A) CI Status (inline — no sub-agent needed)

```bash
HEAD_SHA=$(git rev-parse HEAD)
PR_HEAD=$(gh pr view <N> --json headRefOid -q .headRefOid)
```

If `HEAD_SHA != PR_HEAD`: CI status is `pending` (GitHub hasn't registered latest push). Skip check details.

If they match:
```bash
gh pr view <N> --json statusCheckRollup --jq '.statusCheckRollup[] | [.name, .status, .conclusion, .detailsUrl] | @tsv'
```

Classify:
- **Required** (must be green/skipped):
  - Aether Orchestrator PR (pipeline 446647)
  - Aether Runtime PR Pipeline (pipeline 447965)
- **Non-blocking** (ignore): GitOps/GitHubPop

Conclusion mapping:
- `SUCCESS` / `success` → pass
- `NEUTRAL` / `neutral` / `skipping` → pass (path filters excluded changed files)
- `FAILURE` / `failure` → fail
- `""` / `pending` / `queued` / `in_progress` → pending

Rules:
- Missing required pipeline = **pending** (not green)
- Both required pipelines must be green/skipped
- Both NEUTRAL = merge-eligible (correctly skipped)

Result: `ci_status` = `all_green` | `has_failures` | `pending`, plus `failures[]` list with names and URLs.

### B) Comment Triage (sub-agent)

```
task(agent_type="general-purpose", prompt="
You are triaging comments for PR #<N>.
Read and follow references/comment-triage-agent.md (relative to the ship-it skill directory).
Checkpoint: .ship-it/pr-<N>/checkpoint.json
Repo: <repo> | Hostname: <hostname>
Branch: <branch>
")
```

The triage agent reads the cursor from checkpoint, fetches all 3 comment sources filtered by cursor timestamps, triages every finding, fixes/replies, pushes if needed, and returns a result including the new cursor high-water mark.

---

## Phase 3: Route

Evaluate results from Phase 2. Take the **first matching** action:

| # | Condition | Action |
|---|-----------|--------|
| 1 | Triage agent pushed fixes | Advance cursor to agent's reported high-water mark. Write checkpoint. Exit. |
| 2 | Triage agent found new comments but all were REJECT (no push needed) | Advance cursor. Write checkpoint. Exit. |
| 3 | CI has failures AND no new comments were found | Check `ci_fix_attempts` — if any `category::component::stage` key has 5+ attempts, set `status: "aborted"`, write checkpoint, exit. Otherwise spawn CI Fix Agent. Write checkpoint. Exit. |
| 4 | CI pending AND no new comments | Write checkpoint. Exit. |
| 5 | CI green AND no new comments | Proceed to Merge Gates (Step 4). |

### Spawning CI Fix Agent

```
task(agent_type="general-purpose", prompt="
You are fixing CI failures for PR #<N>.
Read and follow references/ci-fix-agent.md (relative to the ship-it skill directory).
Checkpoint: .ship-it/pr-<N>/checkpoint.json
Repo: <repo> | Branch: <branch>
CI failures: <paste failure names and URLs>
")
```

After CI fix agent returns, update `ci_fix_attempts` in checkpoint (increment the relevant `category::component::stage` key).

### Advancing the Cursor

When the triage agent reports a high-water timestamp:
- Set `cursor.comments_since` = max(current value, agent's high-water mark)
- Set `cursor.reviews_since` = max(current value, agent's high-water mark)
- Set `cursor.last_seen_head_sha` = current HEAD SHA

---

## Step 4: Merge Gates

**All five gates must pass. If ANY gate fails, write checkpoint and exit — the main context will retry next iteration.**

### Gate 1 — HEAD SHA matches PR head
```bash
HEAD_SHA=$(git rev-parse HEAD)
PR_HEAD=$(gh pr view <N> --json headRefOid -q .headRefOid)
```
If mismatch, write checkpoint and exit (GitHub hasn't caught up — main context will retry).

### Gate 2 — Both required pipelines SUCCESS or NEUTRAL
```bash
gh pr checks <N>
gh pr view <N> --json statusCheckRollup --jq '.statusCheckRollup[] | [.name, .status, .conclusion] | @tsv'
```
Both Aether Orchestrator PR (446647) and Aether Runtime PR Pipeline (447965) must show SUCCESS or NEUTRAL for the current HEAD. Missing = fail. Pending = fail.

### Gate 3 — Fresh comment re-check
Re-fetch all 3 comment sources right now:
```bash
gh pr view <N> --json comments --jq '.comments[] | [.id, .createdAt, .author.login, .body[:80]] | @tsv'
gh pr view <N> --json reviews --jq '.reviews[] | [.id, .submittedAt, .author.login, .state, .body[:80]] | @tsv'
gh api --hostname <hostname> repos/<repo>/pulls/<N>/comments --jq '.[] | [.id, .created_at, .user.login, .body[:80]] | @tsv'
```
Check for ANY comment/review with timestamp > `cursor.comments_since` or `cursor.reviews_since`. If new comments exist, go back to Phase 2B (spawn triage agent). Do NOT merge.

### Gate 4 — PR OPEN + mergeable
```bash
gh pr view <N> --json state,mergeable
```
Must be OPEN and MERGEABLE.

### Gate 5 — At least 1 approval exists
```bash
gh pr view <N> --json reviews --jq '[.reviews[] | select(.state == "APPROVED")] | length'
```
Must be >= 1. Note: `CHANGES_REQUESTED` does NOT block merge if all comments have been addressed — `--admin` bypasses this.

### Execute Merge

Only after all five gates pass:
```bash
gh pr merge <N> --admin --squash --delete-branch
```

### Post-Merge
1. Verify: `gh pr view <N> --json state,mergedAt`
2. Update checkpoint: `status: "merged"`
3. Output the Final Report
4. Cleanup: `rm -rf .ship-it/pr-<N>`

---

## Final Report

Output to conversation:

```
## Ship It Report — PR #<N>

### Result: MERGED / ABORTED
### Iterations: <count> of <max>

### Comment Triage Summary
- Implemented: N findings fixed
- Rejected: N findings rejected with rationale
- Blocked: N findings that would cause regressions

### CI Fixes
- <category::component::stage>: <attempts> attempts — <outcome>

### Merge
- Merged at: <timestamp>
- Final HEAD: <sha>
- Branch deleted: <branch>
```

If aborted, include the reason (max iterations, unresolvable conflicts, CI failure budget exhausted, etc.).

---

## Checkpoint Update Protocol

At the END of every iteration:
1. Read current checkpoint via `cat .ship-it/pr-<N>/checkpoint.json`
2. Update `iteration` count
3. Update `cursor` if advanced
4. Update `ci_fix_attempts` if CI was fixed
5. Update `status` if terminal
6. Write back via Bash heredoc

**Never use create/edit tools for checkpoint writes.**
