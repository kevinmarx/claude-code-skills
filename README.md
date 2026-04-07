# claude-code-skills

A collection of [Claude Code skills](https://docs.anthropic.com/en/docs/claude-code/skills) that automate daily development workflows. Each skill is a self-contained directory with a `SKILL.md` (instructions for Claude) and a `README.md` (instructions for humans).

## Skills

### mystatus

Morning dashboard showing Linear tickets and GitHub PRs scoped by organization. Run `/mystatus mai` or `/mystatus gm` to see what needs attention without visiting multiple UIs.

### tmux-title

Automatically sets your tmux tab title to describe what Claude Code is working on. Called proactively at the start of every task.

### worktree-manager

Manages git worktrees with `users/kemarx/*` branch naming conventions. Create, list, switch, and clean up worktrees. Integrates with Linear and ADO for ticket-based branch names.

### gh-account-switcher

Auto-switches the active GitHub CLI account based on workspace directory. Called proactively before any `gh` commands to ensure the right account is active.

### secret-scanner

Pre-commit secret scanner that detects API keys, tokens, and credentials in staged changes. Can also be installed as a git hook.

### token-rotator

Checks token expiry and health across services (GitHub, Azure DevOps, Anthropic, Datadog, Braintrust). Reports which tokens need rotation.

### litellm-diagnostics

Diagnoses the local LiteLLM proxy — checks health, lists models, tails logs, tests end-to-end, and restarts when needed.

### ticket-bridge

Bridges Linear and Azure DevOps tickets with git branches and PRs. Detects ticket references from branches and commits, generates PR descriptions with ticket links, and orchestrates the full ticket-to-branch and PR-to-ticket lifecycle.

### repo-bootstrap

Quick onboarding when entering a repo. Detects project type, checks dependency installation, reports git status, and can install deps with the right package manager.

### architecture-changelog

Detects architectural changes in staged or recent commits (new dependencies, config changes, CI updates, database migrations) and prompts CLAUDE.md updates.

### session-handoff

Saves session context (branch, summary, in-flight files, recent commits) at the end of a work session and restores it at the start of the next one.

## Install

Copy any skill directory into `~/.claude/skills/`:

```bash
cp -r <skill-name> ~/.claude/skills/<skill-name>
```

Or symlink for development:

```bash
ln -s $(pwd)/<skill-name> ~/.claude/skills/<skill-name>
```

Claude Code auto-discovers skills in `~/.claude/skills/`.
