# architecture-changelog

A Claude Code skill that detects architectural changes in your git diffs and drafts CLAUDE.md updates for review.

## Problem

Projects accumulate architectural decisions -- new dependencies, config changes, CI pipelines, test frameworks, database migrations -- but the repo's CLAUDE.md rarely gets updated to reflect them. The next person (or Claude session) working in the repo operates on stale context.

## Solution

This skill runs a detection script against staged changes or recent commits, identifies files that represent architectural shifts, and drafts a CLAUDE.md update. The user always reviews before anything is written.

Detected categories:

- **dependencies** -- package.json, go.mod, Gemfile, Podfile, requirements.txt, pyproject.toml, Cargo.toml
- **config** -- tsconfig, jest/vitest config, eslint, prettier, drizzle config, Docker, Makefile, Rakefile, .env.example
- **ci** -- GitHub Actions workflows, Azure Pipelines, GitLab CI, Jenkinsfile
- **testing** -- test directories, test runner configs, .rspec, pytest.ini
- **database** -- migration directories, Prisma schema, Drizzle migrations

## Install

Copy the skill into your Claude Code skills directory:

```bash
cp -r architecture-changelog ~/.claude/skills/architecture-changelog
```

Claude Code will auto-discover it on the next session.

## How it works

The `detect.sh` script runs `git diff --cached --name-only` (or `git diff HEAD~N --name-only` for commits) and pattern-matches filenames against known architectural file patterns. It outputs a JSON array of categorized changes. Claude reads the output, analyzes what the changes mean, and drafts a CLAUDE.md update for the user to review. Nothing is written without explicit approval.
