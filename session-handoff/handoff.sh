#!/usr/bin/env bash
set -euo pipefail

HANDOFF_DIR="$HOME/.claude/session-handoffs"

usage() {
  cat <<'EOF'
Usage: handoff.sh <command> [options]

Commands:
  save  --repo <path> --summary "text"   Save session context
  load  --repo <path>                    Load most recent handoff for repo
  list  [--limit N]                      List recent handoffs (default 10)
  clean [--days N] [--force]             Remove old handoffs (default 30 days)

Options:
  --help    Show this help message
EOF
  exit 0
}

ensure_dir() {
  mkdir -p "$HANDOFF_DIR"
}

repo_basename() {
  basename "$(cd "$1" && pwd)"
}

# JSON helpers -- use jq if available, otherwise manual construction
has_jq() {
  command -v jq &>/dev/null
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

build_json_array() {
  local input="$1"
  if has_jq; then
    printf '%s' "$input" | jq -R -s 'split("\n") | map(select(length > 0))'
  else
    local first=true
    printf '['
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if $first; then
        first=false
      else
        printf ','
      fi
      printf '"%s"' "$(json_escape "$line")"
    done <<< "$input"
    printf ']'
  fi
}

relative_time() {
  local ts="$1"
  local now
  now=$(date +%s)
  local diff=$(( now - ts ))

  if (( diff < 60 )); then
    echo "just now"
  elif (( diff < 3600 )); then
    echo "$(( diff / 60 )) minutes ago"
  elif (( diff < 86400 )); then
    echo "$(( diff / 3600 )) hours ago"
  else
    echo "$(( diff / 86400 )) days ago"
  fi
}

cmd_save() {
  local repo="" summary=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)    repo="${2:?Error: --repo requires a path}"; shift 2 ;;
      --summary) summary="${2:?Error: --summary requires text}"; shift 2 ;;
      *)         echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  [[ -z "$repo" ]]    && { echo "Error: --repo is required" >&2; exit 1; }
  [[ -z "$summary" ]] && { echo "Error: --summary is required" >&2; exit 1; }

  ensure_dir

  local name
  name=$(repo_basename "$repo")
  local ts
  ts=$(date +%Y-%m-%d-%H%M%S)
  local outfile="$HANDOFF_DIR/${name}-${ts}.json"

  local branch
  branch=$(cd "$repo" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

  local uncommitted
  uncommitted=$(cd "$repo" && git status --porcelain 2>/dev/null || echo "")

  local recent_commits
  recent_commits=$(cd "$repo" && git log --oneline -10 2>/dev/null || echo "")

  local iso_ts
  iso_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local uncommitted_json
  uncommitted_json=$(build_json_array "$uncommitted")

  local commits_json
  commits_json=$(build_json_array "$recent_commits")

  if has_jq; then
    jq -n \
      --arg repo "$repo" \
      --arg branch "$branch" \
      --arg summary "$summary" \
      --arg timestamp "$iso_ts" \
      --argjson uncommitted_files "$uncommitted_json" \
      --argjson recent_commits "$commits_json" \
      '{repo: $repo, branch: $branch, summary: $summary, timestamp: $timestamp, uncommitted_files: $uncommitted_files, recent_commits: $recent_commits}' \
      > "$outfile"
  else
    cat > "$outfile" <<ENDJSON
{
  "repo": "$(json_escape "$repo")",
  "branch": "$(json_escape "$branch")",
  "summary": "$(json_escape "$summary")",
  "timestamp": "$iso_ts",
  "uncommitted_files": $uncommitted_json,
  "recent_commits": $commits_json
}
ENDJSON
  fi

  echo "$outfile"
}

cmd_load() {
  local repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:?Error: --repo requires a path}"; shift 2 ;;
      *)      echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  [[ -z "$repo" ]] && { echo "Error: --repo is required" >&2; exit 1; }

  ensure_dir

  local name
  name=$(repo_basename "$repo")

  # Find the most recent handoff file for this repo
  local latest
  latest=$(find "$HANDOFF_DIR" -maxdepth 1 -name "${name}-*.json" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)

  if [[ -z "$latest" ]]; then
    echo "No handoff found for $name"
    exit 0
  fi

  local summary branch timestamp uncommitted commits

  if has_jq; then
    summary=$(jq -r '.summary' "$latest")
    branch=$(jq -r '.branch' "$latest")
    timestamp=$(jq -r '.timestamp' "$latest")
    uncommitted=$(jq -r '.uncommitted_files[]' "$latest" 2>/dev/null || echo "")
    commits=$(jq -r '.recent_commits[]' "$latest" 2>/dev/null || echo "")
  else
    # Minimal fallback parsing with grep/sed
    summary=$(grep -o '"summary": *"[^"]*"' "$latest" | sed 's/"summary": *"//;s/"$//')
    branch=$(grep -o '"branch": *"[^"]*"' "$latest" | sed 's/"branch": *"//;s/"$//')
    timestamp=$(grep -o '"timestamp": *"[^"]*"' "$latest" | sed 's/"timestamp": *"//;s/"$//')
    uncommitted=""
    commits=""
  fi

  # Compute relative time
  local epoch_ts rel_time
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s &>/dev/null 2>&1; then
    # macOS
    epoch_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s)
  elif date -d "$timestamp" +%s &>/dev/null 2>&1; then
    # GNU/Linux
    epoch_ts=$(date -d "$timestamp" +%s)
  else
    epoch_ts=$(date +%s)
  fi
  rel_time=$(relative_time "$epoch_ts")

  echo "=== Session Handoff ($rel_time) ==="
  echo "Branch: $branch"
  echo ""
  echo "Summary:"
  echo "  $summary"

  if [[ -n "$uncommitted" ]]; then
    echo ""
    echo "In-flight files:"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "  $line"
    done <<< "$uncommitted"
  fi

  if [[ -n "$commits" ]]; then
    echo ""
    echo "Recent commits:"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "  $line"
    done <<< "$commits"
  fi
}

cmd_list() {
  local limit=10
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="${2:?Error: --limit requires a number}"; shift 2 ;;
      *)       echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  ensure_dir

  local files
  files=$(find "$HANDOFF_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -"$limit" || true)

  if [[ -z "$files" ]]; then
    echo "No handoffs found."
    exit 0
  fi

  printf "%-20s %-20s %s\n" "REPO" "DATE" "SUMMARY"
  printf "%-20s %-20s %s\n" "----" "----" "-------"

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local fname
    fname=$(basename "$f")

    local repo_name date_part summary

    if has_jq; then
      repo_name=$(jq -r '.repo' "$f" | xargs basename)
      date_part=$(jq -r '.timestamp' "$f" | cut -dT -f1)
      summary=$(jq -r '.summary' "$f")
    else
      repo_name=$(grep -o '"repo": *"[^"]*"' "$f" | sed 's/"repo": *"//;s/"$//' | xargs basename)
      date_part=$(grep -o '"timestamp": *"[^"]*"' "$f" | sed 's/"timestamp": *"//;s/"$//' | cut -dT -f1)
      summary=$(grep -o '"summary": *"[^"]*"' "$f" | sed 's/"summary": *"//;s/"$//')
    fi

    # Truncate summary to 80 chars
    if [[ ${#summary} -gt 80 ]]; then
      summary="${summary:0:77}..."
    fi

    printf "%-20s %-20s %s\n" "$repo_name" "$date_part" "$summary"
  done <<< "$files"
}

cmd_clean() {
  local days=30 force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)  days="${2:?Error: --days requires a number}"; shift 2 ;;
      --force) force=true; shift ;;
      *)       echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  ensure_dir

  local old_files
  old_files=$(find "$HANDOFF_DIR" -name "*.json" -mtime +"$days" 2>/dev/null || true)

  if [[ -z "$old_files" ]]; then
    echo "No handoffs older than $days days."
    exit 0
  fi

  local count
  count=$(echo "$old_files" | wc -l | tr -d ' ')
  echo "Found $count handoff(s) older than $days days:"
  echo "$old_files" | while IFS= read -r f; do
    echo "  $(basename "$f")"
  done

  if ! $force; then
    printf "\nRemove these files? [y/N] "
    read -r answer
    [[ "$answer" != "y" && "$answer" != "Y" ]] && { echo "Aborted."; exit 0; }
  fi

  echo "$old_files" | while IFS= read -r f; do
    rm -f "$f"
  done
  echo "Removed $count handoff(s)."
}

# Main dispatch
[[ $# -eq 0 ]] && usage

case "${1:-}" in
  save)    shift; cmd_save "$@" ;;
  load)    shift; cmd_load "$@" ;;
  list)    shift; cmd_list "$@" ;;
  clean)   shift; cmd_clean "$@" ;;
  --help)  usage ;;
  -h)      usage ;;
  *)       echo "Unknown command: $1" >&2; usage ;;
esac
