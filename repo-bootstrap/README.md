# repo-bootstrap

A Claude Code skill that automatically orients in any repository by detecting the project type, checking dependency health, and offering to install missing dependencies.

## Problem

When you jump between repositories -- especially in worktrees or unfamiliar codebases -- there is always the same set of questions: What kind of project is this? Are deps installed? Is the branch clean? Are there project-specific instructions? Answering these manually every time is tedious.

## Solution

This skill tells Claude to proactively run a bootstrap check when entering a repo. It detects the project type from manifest files, checks whether dependencies are installed, reports git status, and flags whether a `.claude/CLAUDE.md` exists. If deps are missing, it offers to run the correct install command.

Supported project types:

- Node (package.json) -- detects npm, yarn, or pnpm from lockfile
- Go (go.mod)
- Ruby (Gemfile)
- Python (pyproject.toml or requirements.txt)
- Swift (Package.swift)
- Rust (Cargo.toml)

## Install

Copy the skill into your Claude Code skills directory:

```bash
cp -r repo-bootstrap ~/.claude/skills/repo-bootstrap
```

Claude Code will automatically discover the skill and start using it when entering repositories.

## How it works

The `SKILL.md` file instructs Claude to proactively run `bootstrap.sh status` when entering a repo. The script detects project types from manifest files, checks for dependency directories (`node_modules/`, `vendor/`, `.build/`, `target/`), reports git branch and sync state, and checks for `.claude/CLAUDE.md`. Claude then combines this with any prior context from local-memory MCP and reports a concise summary. If dependencies are missing, Claude offers to run `bootstrap.sh install` which picks the right package manager command.
