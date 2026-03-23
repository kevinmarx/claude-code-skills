#!/usr/bin/env bash
# Set the tmux pane title to describe current work
# Usage: bash set-title.sh "short task description"

title="${1:?Usage: set-title.sh \"short title\"}"

# Set the pane title via ANSI escape sequence
printf '\033]2;%s\033\\' "$title"

# Also set it via tmux directly if we're in a tmux session
if [ -n "$TMUX" ]; then
    tmux rename-window "$title"
fi

echo "Title set: $title"
