---
name: repo-bootstrap
version: 1.0.0
description: Detect project type, check dependency health, and bootstrap repos. Use proactively when entering a new or unfamiliar repository.
---

# repo-bootstrap

Quickly orient in any repository by detecting the project type, dependency state, and git health.

## When to Use

**Call this proactively:**
- When you first enter a repository or worktree
- When the user switches to a different project
- When you need to verify the repo is in a good state before starting work

## Workflow

1. Run status to understand the repo:

```bash
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh status --path /path/to/repo
```

2. Check local-memory MCP for past context on this repo:

```
recall("repo name or path keywords")
```

3. Read `.claude/CLAUDE.md` if it exists for project-specific instructions.

4. Report a concise summary to the user: project type, dep health, git state, and any prior context found.

5. If dependencies are not installed, offer to run install:

```bash
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh install --path /path/to/repo --yes
```

## Commands

### status

Detect project type and report health. Outputs a concise 5-10 line plain text report.

```bash
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh status
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh status --path /some/repo
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh status --path /some/repo --json
```

### install

Run the correct install command for the detected project type.

```bash
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh install --path /some/repo
bash ~/.claude/skills/repo-bootstrap/bootstrap.sh install --path /some/repo --yes
```
