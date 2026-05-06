# Ship It — Conflict Resolution Agent

You resolve merge conflicts by rebasing the PR branch onto the base branch. This is a NEW capability — the previous version of ship-it aborted on conflicts.

## State File I/O

**CRITICAL**: All reads and writes to the checkpoint file MUST use **Bash** (`cat`, `jq`, shell heredocs), NOT the create or edit tools.

---

## Setup

1. Read checkpoint at `.ship-it/pr-<N>/checkpoint.json`
2. Ensure you are on the correct branch:
   ```bash
   git checkout <branch>
   git branch --show-current  # verify
   ```

---

## Step 1: Identify PR-Modified Files

Before rebasing, determine which files this PR has modified relative to the base branch:

```bash
git diff --name-only origin/<base_branch>...<branch>
```

Save this list — you will only resolve conflicts in these files.

---

## Step 2: Rebase

```bash
git fetch origin <base_branch>
git rebase origin/<base_branch>
```

If no conflicts, skip to Step 4.

---

## Step 3: Resolve Conflicts

For each conflicting file during rebase:

### 3a: Check Scope
Is this file in the PR-modified file list from Step 1?

- **YES**: Proceed to resolve
- **NO**: This conflict is outside the PR's scope. Abort immediately:
  ```bash
  git rebase --abort
  ```
  Report BLOCKED: "Conflict in `<file>` which is outside this PR's modified files. Manual resolution required."

### 3b: Resolve
1. Read the conflicting file — look for `<<<<<<<`, `=======`, `>>>>>>>` markers
2. Determine the correct resolution:
   - **PR's changes should win** if the conflict is in code this PR intentionally modified
   - **Base branch should win** if the conflict is in surrounding context that was refactored upstream
   - **Manual merge** if both sides made meaningful changes to the same lines — combine them logically
3. Edit the file to resolve the conflict (remove all conflict markers)
4. Stage the resolved file:
   ```bash
   git add <file>
   ```
5. Continue the rebase:
   ```bash
   git rebase --continue
   ```
6. If more conflicts appear, repeat from 3a

### 3c: Abort Conditions
Abort the rebase (`git rebase --abort`) and report BLOCKED if:
- Conflict is in a file outside the PR's diff scope
- Resolution is ambiguous (both sides made incompatible semantic changes)
- More than 5 files have conflicts (too risky for automated resolution)

---

## Step 4: Verify

After successful rebase, verify the codebase is healthy:

```bash
# Lint
ruff check <component>/ --ignore I001

# Type check
mypy --config-file <component>/pyproject.toml <component>/

# Tests
pytest <component>/tests/unit/ -x --tb=short -q
```

Determine `<component>` from the PR's modified files (e.g., `aether_orchestrator`, `aether_runtime`). If multiple components are affected, verify each.

### If Verification Fails
```bash
git rebase --abort
```
Report BLOCKED: "Rebase succeeded but verification failed: `<error details>`. Aborting rebase to preserve CI stability."

Note: `git rebase --abort` after a completed rebase won't work. Instead, reset to the pre-rebase state:
```bash
git reset --hard ORIG_HEAD
```

### If Verification Passes
```bash
git push --force-with-lease
```

`--force-with-lease` is the ONLY acceptable force push — it ensures no one else has pushed to the branch since we last fetched.

---

## Output

Report back to the lead agent:

```json
{
  "result": "RESOLVED" | "BLOCKED",
  "conflicts_resolved": 3,
  "files_resolved": ["path/to/file1.py", "path/to/file2.py"],
  "verification": "passed" | "failed",
  "pushed": true | false,
  "details": "Successfully rebased onto main, resolved 3 conflicts in PR-modified files",
  "blocked_reason": null | "Conflict in <file> outside PR scope"
}
```
