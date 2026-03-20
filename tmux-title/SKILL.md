---
name: tmux-title
version: 1.0.0
description: Set the tmux pane title to describe what Claude Code is currently working on. Call this proactively at the start of any task or when context shifts.
---

# tmux-title

Set the tmux pane title so the user can see what each Claude Code session is working on.

## When to Use

**Call this proactively:**
- At the start of every new task or conversation
- When the focus of work shifts significantly
- Keep titles very short (2-4 words max)

## Usage

```bash
bash ~/.claude/skills/tmux-title/set-title.sh "eval scoring fix"
```

## Title Guidelines

- **2-4 words max** — it needs to fit in a tmux tab
- Describe the task, not the repo (the repo is already visible)
- Examples: `fix auth pool`, `add retry logic`, `browser eval debug`, `pr review`, `slides scorer`
- No punctuation, no prefixes, just the gist
