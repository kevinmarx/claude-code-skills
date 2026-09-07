# KM Review Check

`km-review-check` identifies actionable GitHub pull-request review feedback
that is still open. It collects top-level PR comments, review summaries, inline
comments, and resolved-thread state, then compares findings with the current PR
head. It counts unique requested changes, not comments or review events, and
reports human approvals, per-artifact responses, reviewer acceptance, and
review coverage separately. Triage is read-only; only an explicitly selected
action may modify the PR head branch or PR conversation.

## Install

Copy or symlink the `km-review-check` directory into Claude Code's skills
directory:

```bash
cp -r km-review-check ~/.claude/skills/km-review-check
```

For development from this repository:

```bash
ln -s "$(pwd)/km-review-check" ~/.claude/skills/km-review-check
```

Claude Code detects changes in an existing skills directory during the current
session. Restart it only when creating that top-level directory for the first
time.

## Usage

```text
/km-review-check 1234
/km-review-check https://github.com/owner/repository/pull/1234
/km-review-check https://github.example.com/owner/repository/pull/1234
```

Use a PR number for the repository in the current directory, or give a full PR
URL for any GitHub.com or GitHub Enterprise Server repository available through
the active `gh` account. With no argument, the skill attempts to resolve the PR
for the current branch and asks for an identifier if none exists.

## What It Does

1. Snapshots the PR head and retrieves every feedback surface, including
   paginated top-level PR conversation comments regardless of formal review
   state or reviewer assignment.
2. Reconstructs inline review threads and reads GitHub's resolution state when
   GraphQL access is available.
3. Separates marker-only comments from review coverage failures. Parses author
   replies and triage receipts as response evidence without treating them as
   new findings.
4. Splits substantive comments into concrete requests and deduplicates repeated
   implementation findings while retaining every source artifact and any later
   requirement.
5. Evaluates implementation from current-head content independently of human
   approvals, per-artifact responses, reviewer acceptance, and coverage gaps.
6. Runs a deterministic renderer that validates the normalized triage, computes
   orthogonal counts, and refuses to report a full all-clear while any lifecycle
   action remains.
7. Offers only applicable next actions: fix source findings, publish artifact
   dispositions, request human/reviewer follow-up, or post the triage. Every
   write requires explicit approval and a fresh PR-head check.

The skill performs triage through read-only GitHub and Git operations. When
asked to fix all unaddressed findings, it reuses the worktree for the PR head
branch when available and creates a branch worktree only as a fallback. It
validates, commits, and pushes focused fixes to the PR head branch without
switching branches in the caller's worktree, force-pushing, resolving threads,
or merging.

## Understanding the Output

The report distinguishes implementation work from every review-lifecycle axis:

```text
0 need changes; 0 contested; 0 unverified; 2 addressed.
2 unique findings assessed at <head SHA>.
Lifecycle: 3 source artifacts need responses; 2 human actions; 2 reviewer
follow-ups; 1 review coverage gap. Thread resolution is tracked separately.
```

For example, 19 historical review/comment artifacts can contain repeated
reports of two issues plus setup notices. If both issues are fixed at the
current head, the result is **zero findings needing changes**, not "19
unanswered." But the report still names every findings-bearing artifact that
lacks a source-specific disposition, every required human approval, every
reviewer awaiting follow-up, and every failed review run. An author's reply
proves neither a fix nor reviewer acceptance.

The skill does not use a repository status script's raw artifact count as its
finding count or echo its "STOP, unanswered feedback" recommendation.

| Situation | Expected classification |
| --- | --- |
| The same missing change appears in a review, a top-level comment, and an inline thread | One unaddressed finding, with all three source links. |
| One comment asks for two independent changes, and only one is present | One addressed and one unaddressed finding. |
| The current file satisfies an old request, but its reviewer still requests changes | Addressed finding; reviewer sign-off reported separately. |
| A fixed finding appears in three artifacts but only one received an author response | One addressed implementation finding; two artifact response gaps. |
| A review requires security or architecture sign-off | Pending human action; never source-addressed or self-approved by the PR author. |
| A thread is resolved but its requested source change is absent | Unaddressed implementation; thread resolution is lifecycle evidence only. |
| A requested reviewer failed during setup | Review coverage gap, not an implementation finding. |
| An older author explanation is followed by a source-verified fix | Addressed, not contested merely because the explanation aged past 24 hours. |
| A task-created notice comes from an ordinary-looking user account | Not a finding. |
| A later comment adds an unmet requirement to an otherwise fixed topic | Retain and assess the new requirement; do not hide it as a duplicate. |
| The relevant current file cannot be read | Unverified, not unaddressed or addressed by assumption. |

The skill reports a full all-clear only when implementation and every lifecycle
axis are closed. It never offers another code fix merely to clear a formal
blocking verdict.

## Requirements

- GitHub CLI (`gh`) installed and authenticated for the target GitHub host.
- Python 3, using only the standard library, for deterministic triage rendering.
- Permission to read the pull request, its comments, and its files.
- Permission to push the PR head branch when fixing unaddressed findings.
- Permission to clone the PR head repository when fixing a cross-repository PR
  that has no local clone or reusable worktree.
- GraphQL access is recommended for resolved-thread state. If unavailable, the
  report explicitly identifies that resolution state could not be confirmed.

## Tests

Run the deterministic lifecycle regression suite with:

```bash
python3 -m unittest discover -s km-review-check/tests -p 'test_*.py'
```

The fixture in `testdata/pr-12131-lifecycle.json` pins the failure mode where
all source changes are present but artifact responses, human approvals,
reviewer acceptance, and review coverage are still open.

## Boundaries

Use this skill to **triage existing feedback**. After triage, the user may
explicitly choose **Fix all unaddressed findings**; that option only changes
findings classified as unaddressed in the PR branch's existing worktree, or a
new worktree when none exists. The skill may commit and push those validated
fixes to the PR head branch, but it does not perform a fresh code review,
force-push, resolve review threads, or merge a PR. Both fixing findings and
posting require explicit approval. Human approvals, artifact responses, and
reviewer follow-up remain separate actions, each requires its own displayed
authorization, and none authorizes source changes implicitly.
