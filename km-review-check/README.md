# KM Review Check

`km-review-check` identifies actionable GitHub pull-request review feedback
that is still open. It collects top-level PR comments, review summaries, inline
comments, and resolved-thread state, then compares findings with the current PR
head without checking out or modifying the target branch.

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

1. Snapshots the PR head and retrieves every review-feedback surface.
2. Reconstructs inline review threads and reads GitHub's resolution state when
   GraphQL access is available.
3. Filters non-findings, including bot status, acknowledgements, and questions
   that do not request a change.
4. Classifies actionable findings as addressed, unaddressed, contested, or
   unverifiable, using reviewer acceptance, thread resolution, post-review
   commits, and current PR file content.
5. Displays only unresolved, contested, and unverifiable findings grouped by
   severity.
6. Optionally posts or updates a sentinel-marked triage comment after explicit
   approval and a fresh PR-head check.

The skill performs all analysis through read-only GitHub and Git operations.
It never checks out the PR branch, resolves threads, pushes changes, or merges.

## Requirements

- GitHub CLI (`gh`) installed and authenticated for the target GitHub host.
- Permission to read the pull request, its comments, and its files.
- GraphQL access is recommended for resolved-thread state. If unavailable, the
  report explicitly identifies that resolution state could not be confirmed.

## Boundaries

Use this skill to **triage existing feedback**. It does not implement fixes,
perform a fresh code review, or merge a PR. Posting the generated triage is the
only remote write, and it always requires explicit approval.
