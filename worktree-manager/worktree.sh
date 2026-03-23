#!/usr/bin/env bash
set -euo pipefail

# worktree-manager: git worktree management with users/kemarx/* branch conventions

BRANCH_PREFIX="users/kemarx"

usage() {
  cat <<EOF
Usage: worktree.sh <subcommand> [args]

Subcommands:
  new <name> [--base <branch>]   Create a new worktree with branch users/kemarx/<name>
  list                           List all worktrees with status
  clean [--force]                Remove worktrees for merged/deleted branches
  switch <name>                  Print path to a worktree matching <name>
EOF
  exit 1
}

# Ensure we're in a git repo and find the root
ensure_git_repo() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 1
  fi
}

# Get the repo root (handles both main repo and worktree contexts)
get_main_worktree() {
  git worktree list --porcelain | head -1 | sed 's/^worktree //'
}

# Get the repo directory name from the main worktree
get_repo_name() {
  basename "$(get_main_worktree)"
}

# Auto-detect default branch (main or master)
detect_default_branch() {
  local remote="${1:-origin}"
  # Check remote HEAD first
  local head_ref
  head_ref=$(git symbolic-ref "refs/remotes/${remote}/HEAD" 2>/dev/null | sed "s|refs/remotes/${remote}/||" || true)
  if [[ -n "$head_ref" ]]; then
    echo "$head_ref"
    return
  fi
  # Fall back to checking if main or master exist
  if git show-ref --verify --quiet "refs/remotes/${remote}/main" 2>/dev/null; then
    echo "main"
  elif git show-ref --verify --quiet "refs/remotes/${remote}/master" 2>/dev/null; then
    echo "master"
  else
    echo "error: could not detect default branch (tried main, master)" >&2
    exit 1
  fi
}

# --- Subcommand: new ---
# Note: Claude may pre-process Linear ticket IDs (e.g., GRO-123) or ADO work item IDs
# (e.g., 12345) into slugified names (e.g., gro-123-fix-push-notification-badge-count)
# before calling this script. The name argument accepts any string valid for git branch
# names — no pattern restrictions are enforced here.
cmd_new() {
  local name=""
  local base=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        base="$2"
        shift 2
        ;;
      -*)
        echo "error: unknown flag $1" >&2
        exit 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          echo "error: unexpected argument $1" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$name" ]]; then
    echo "error: name required. Usage: worktree.sh new <name> [--base <branch>]" >&2
    exit 1
  fi

  local repo_name
  repo_name=$(get_repo_name)
  local main_worktree
  main_worktree=$(get_main_worktree)
  local parent_dir
  parent_dir=$(dirname "$main_worktree")

  local branch="${BRANCH_PREFIX}/${name}"
  local worktree_path="${parent_dir}/${repo_name}-${name}"

  if [[ -z "$base" ]]; then
    base=$(detect_default_branch)
  fi

  # Fetch latest
  echo "Fetching latest from origin..."
  git fetch origin "$base" --quiet

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
    echo "Branch ${branch} already exists, creating worktree from existing branch..."
    git worktree add "$worktree_path" "$branch"
  else
    git worktree add -b "$branch" "$worktree_path" "origin/${base}"
  fi

  echo "$worktree_path"
}

# --- Subcommand: list ---
cmd_list() {
  printf "%-50s %-40s %s\n" "PATH" "BRANCH" "STATUS"
  printf "%-50s %-40s %s\n" "----" "------" "------"

  while IFS=$'\t' read -r wt_path wt_branch; do
    local status="clean"
    if [[ -d "$wt_path" ]]; then
      if git -C "$wt_path" diff --quiet 2>/dev/null && git -C "$wt_path" diff --cached --quiet 2>/dev/null; then
        status="clean"
      else
        status="dirty"
      fi
      # Also check for untracked files
      if [[ -n $(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null) ]]; then
        status="dirty"
      fi
    else
      status="missing"
    fi
    # Shorten branch for display
    local short_branch="${wt_branch#refs/heads/}"
    printf "%-50s %-40s %s\n" "$wt_path" "$short_branch" "$status"
  done < <(
    git worktree list --porcelain | awk '
      /^worktree / { path = substr($0, 10) }
      /^branch /   { branch = substr($0, 8) }
      /^HEAD /     { head = substr($0, 6) }
      /^bare$/     { branch = "(bare)" }
      /^detached$/ { branch = "(detached)" }
      /^$/ {
        if (path != "") {
          print path "\t" branch
        }
        path = ""; branch = ""; head = ""
      }
      END {
        if (path != "") {
          print path "\t" branch
        }
      }
    '
  )
}

# --- Subcommand: clean ---
cmd_clean() {
  local force=false
  if [[ "${1:-}" == "--force" ]]; then
    force=true
  fi

  # Prune worktrees pointing to missing directories first
  git worktree prune

  local to_remove=()

  # Fetch to get latest remote state
  git fetch --prune --quiet

  while IFS=$'\t' read -r wt_path wt_branch; do
    # Skip bare/detached/main worktree
    [[ -z "$wt_branch" || "$wt_branch" == "(bare)" || "$wt_branch" == "(detached)" ]] && continue
    local short_branch="${wt_branch#refs/heads/}"

    # Skip if it's the main worktree
    local main_wt
    main_wt=$(get_main_worktree)
    [[ "$wt_path" == "$main_wt" ]] && continue

    local should_remove=false

    # Check if branch was deleted on remote
    if [[ "$short_branch" == "${BRANCH_PREFIX}/"* ]]; then
      local remote_ref="refs/remotes/origin/${short_branch}"
      if ! git show-ref --verify --quiet "$remote_ref" 2>/dev/null; then
        # Branch doesn't exist on remote — check if it was merged
        local default_branch
        default_branch=$(detect_default_branch)
        if git merge-base --is-ancestor "refs/heads/${short_branch}" "origin/${default_branch}" 2>/dev/null; then
          should_remove=true
        fi
      fi

      # Also check if remote branch was explicitly deleted (tracking gone)
      local upstream
      upstream=$(git for-each-ref --format='%(upstream)' "refs/heads/${short_branch}" 2>/dev/null || true)
      if [[ -n "$upstream" ]] && ! git show-ref --verify --quiet "$upstream" 2>/dev/null; then
        should_remove=true
      fi
    fi

    if $should_remove; then
      to_remove+=("$wt_path|$short_branch")
    fi
  done < <(
    git worktree list --porcelain | awk '
      /^worktree / { path = substr($0, 10) }
      /^branch /   { branch = substr($0, 8) }
      /^bare$/     { branch = "(bare)" }
      /^detached$/ { branch = "(detached)" }
      /^$/ {
        if (path != "") { print path "\t" branch }
        path = ""; branch = ""
      }
      END {
        if (path != "") { print path "\t" branch }
      }
    '
  )

  if [[ ${#to_remove[@]} -eq 0 ]]; then
    echo "No stale worktrees found."
    return
  fi

  echo "Stale worktrees:"
  for entry in "${to_remove[@]}"; do
    local wt_path="${entry%%|*}"
    local wt_branch="${entry##*|}"
    echo "  ${wt_path}  (${wt_branch})"
  done

  if ! $force; then
    echo ""
    read -r -p "Remove these worktrees and branches? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Aborted."
      return
    fi
  fi

  for entry in "${to_remove[@]}"; do
    local wt_path="${entry%%|*}"
    local wt_branch="${entry##*|}"
    echo "Removing worktree: ${wt_path}"
    git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
    echo "Deleting branch: ${wt_branch}"
    git branch -D "$wt_branch" 2>/dev/null || true
  done

  echo "Done."
}

# --- Subcommand: switch ---
cmd_switch() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "error: name required. Usage: worktree.sh switch <name>" >&2
    exit 1
  fi

  local matches=()

  while IFS=$'\t' read -r wt_path wt_branch; do
    [[ -z "$wt_branch" ]] && continue
    local short_branch="${wt_branch#refs/heads/}"
    # Match against path basename or branch name
    if [[ "$wt_path" == *"$name"* || "$short_branch" == *"$name"* ]]; then
      matches+=("$wt_path")
    fi
  done < <(
    git worktree list --porcelain | awk '
      /^worktree / { path = substr($0, 10) }
      /^branch /   { branch = substr($0, 8) }
      /^bare$/     { branch = "(bare)" }
      /^detached$/ { branch = "(detached)" }
      /^$/ {
        if (path != "") { print path "\t" branch }
        path = ""; branch = ""
      }
      END {
        if (path != "") { print path "\t" branch }
      }
    '
  )

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "error: no worktree found matching '$name'" >&2
    exit 1
  elif [[ ${#matches[@]} -gt 1 ]]; then
    echo "error: multiple worktrees match '$name':" >&2
    for m in "${matches[@]}"; do
      echo "  $m" >&2
    done
    exit 1
  fi

  echo "${matches[0]}"
}

# --- Main ---
ensure_git_repo

subcommand="${1:-}"
shift || true

case "$subcommand" in
  new)    cmd_new "$@" ;;
  list)   cmd_list "$@" ;;
  clean)  cmd_clean "$@" ;;
  switch) cmd_switch "$@" ;;
  *)      usage ;;
esac
