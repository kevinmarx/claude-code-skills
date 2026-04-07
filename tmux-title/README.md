# tmux-title

A Claude Code skill that automatically sets your tmux tab title to describe what Claude Code is working on.

## Problem

When running multiple Claude Code sessions in tmux, every tab just shows the directory name or `claude`. You can't tell at a glance what each session is doing.

## Solution

This skill tells Claude to proactively call a script at the start of every task that sets the tmux window name to a short description of the current work.

Your tabs go from:

```
1:repo  2:bash  3:repo
```

To:

```
1:fix auth pool  2:eval scoring  3:pr review
```

## Install

1. Copy the skill into your Claude Code skills directory:

```bash
cp -r tmux-title ~/.claude/skills/tmux-title
```

2. Add to your `~/.tmux.conf` (or `~/.tmux.conf.local`):

```bash
setw -g automatic-rename off
set -g allow-rename on
```

3. Reload tmux config:

```
tmux source-file ~/.tmux.conf
```

That's it. Claude Code will automatically discover the skill and start using it.

## How it works

The `SKILL.md` file instructs Claude to proactively run `set-title.sh` at the start of tasks with a 2-4 word description. The script sets the tmux window name via both ANSI escape sequences and `tmux rename-window`.
