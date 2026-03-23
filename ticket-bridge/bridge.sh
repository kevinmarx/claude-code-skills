#!/usr/bin/env bash
set -euo pipefail

# ticket-bridge: detect ticket refs, format PR descriptions, manage config

SETTINGS_FILE=".claude/settings.local.json"

# --- helpers ---

check_jq() {
  if ! command -v jq &>/dev/null; then
    echo "WARNING: jq is not installed. Some features will not work." >&2
    echo "Install: brew install jq (macOS) or apt install jq (Linux)" >&2
    return 1
  fi
}

usage() {
  cat <<'EOF'
Usage: bridge.sh <subcommand> [options]

Subcommands:
  detect                   Parse branch name + recent commits for ticket refs
    --branch-only          Only check the branch name, skip commits
    --path <dir>           Run from a specific directory

  format-pr --tickets "GRO-123,AB#456"
                           Generate PR description markdown with ticket links
    --path <dir>           Read config from this repo directory

  config --repo <path>     Show or set ticket mapping config
    --set --linear-team <team> --ado-project <project> --ado-org <org>

Examples:
  bridge.sh detect
  bridge.sh detect --branch-only --path /Users/kemarx/workspace/mai/app
  bridge.sh format-pr --tickets "GRO-123,AB#456"
  bridge.sh config --repo .
  bridge.sh config --repo . --set --linear-team groupme --ado-project GroupMe --ado-org nickelgroup
EOF
}

# --- detect ---

detect_tickets() {
  local branch_only=false
  local target_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch-only) branch_only=true; shift ;;
      --path) target_dir="${2:?Error: --path requires a directory}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  check_jq || exit 1

  local refs=()

  # Parse branch name
  local branch
  branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if [[ -n "$branch" ]]; then
    # Linear: ABC-123 pattern
    while IFS= read -r match; do
      [[ -n "$match" ]] && refs+=("{\"type\":\"linear\",\"id\":\"$match\"}")
    done < <(echo "$branch" | grep -oE '[A-Z]+-[0-9]+' || true)

    # ADO: AB#12345 (require AB# prefix to avoid false positives)
    while IFS= read -r match; do
      local num="${match#AB#}"
      [[ -n "$num" ]] && refs+=("{\"type\":\"ado\",\"id\":\"$num\"}")
    done < <(echo "$branch" | grep -oE 'AB#[0-9]+' || true)
  fi

  # Parse last 5 commit messages
  if [[ "$branch_only" == false ]]; then
    local commits
    commits=$(git -C "$target_dir" log -5 --pretty=format:"%s" 2>/dev/null || echo "")

    if [[ -n "$commits" ]]; then
      while IFS= read -r match; do
        [[ -n "$match" ]] && refs+=("{\"type\":\"linear\",\"id\":\"$match\"}")
      done < <(echo "$commits" | grep -oE '[A-Z]+-[0-9]+' || true)

      while IFS= read -r match; do
        local num="${match#AB#}"
        [[ -n "$num" ]] && refs+=("{\"type\":\"ado\",\"id\":\"$num\"}")
      done < <(echo "$commits" | grep -oE 'AB#[0-9]+' || true)
    fi
  fi

  # Deduplicate and output as JSON array
  if [[ ${#refs[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${refs[@]}" | jq -s 'unique_by(.type + .id)'
  fi
}

# --- format-pr ---

format_pr() {
  local tickets=""
  local target_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tickets) tickets="${2:?Error: --tickets requires a value}"; shift 2 ;;
      --path) target_dir="${2:?Error: --path requires a directory}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$tickets" ]]; then
    echo "Error: --tickets is required" >&2
    exit 1
  fi

  check_jq || exit 1

  # Read config if available
  local linear_team="" ado_org="" ado_project=""
  local settings="${target_dir}/${SETTINGS_FILE}"
  if [[ -f "$settings" ]]; then
    linear_team=$(jq -r '.ticketBridge.linearTeam // empty' "$settings" 2>/dev/null || true)
    ado_org=$(jq -r '.ticketBridge.adoOrg // empty' "$settings" 2>/dev/null || true)
    ado_project=$(jq -r '.ticketBridge.adoProject // empty' "$settings" 2>/dev/null || true)
  fi

  echo "## Linked Tickets"
  echo ""

  IFS=',' read -ra ticket_list <<< "$tickets"
  for ticket in "${ticket_list[@]}"; do
    ticket=$(echo "$ticket" | xargs) # trim whitespace

    if [[ "$ticket" =~ ^[A-Z]+-[0-9]+$ ]]; then
      # Linear ticket
      if [[ -n "$linear_team" ]]; then
        echo "- [${ticket}](https://linear.app/${linear_team}/issue/${ticket})"
      else
        echo "- ${ticket}"
      fi

    elif [[ "$ticket" =~ ^AB#([0-9]+)$ ]] || [[ "$ticket" =~ ^([0-9]+)$ ]]; then
      # ADO work item
      local id="${BASH_REMATCH[1]}"
      if [[ -n "$ado_org" && -n "$ado_project" ]]; then
        echo "- [AB#${id}](https://dev.azure.com/${ado_org}/${ado_project}/_workitems/edit/${id})"
      else
        echo "- AB#${id}"
      fi

    else
      echo "- ${ticket}"
    fi
  done
}

# --- config ---

config_cmd() {
  local repo_path=""
  local do_set=false
  local linear_team="" ado_project="" ado_org=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_path="${2:?Error: --repo requires a path}"; shift 2 ;;
      --set) do_set=true; shift ;;
      --linear-team) linear_team="${2:?Error: --linear-team requires a value}"; shift 2 ;;
      --ado-project) ado_project="${2:?Error: --ado-project requires a value}"; shift 2 ;;
      --ado-org) ado_org="${2:?Error: --ado-org requires a value}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$repo_path" ]]; then
    echo "Error: --repo is required" >&2
    exit 1
  fi

  check_jq || exit 1

  local settings="${repo_path}/${SETTINGS_FILE}"

  if [[ "$do_set" == false ]]; then
    # Show current config
    if [[ -f "$settings" ]]; then
      jq '.ticketBridge // "No ticket-bridge config found"' "$settings"
    else
      echo "No settings file found at ${settings}"
    fi
    return
  fi

  # Set config
  mkdir -p "$(dirname "$settings")"

  local existing="{}"
  if [[ -f "$settings" ]]; then
    existing=$(cat "$settings")
  fi

  local bridge_config="{}"
  [[ -n "$linear_team" ]] && bridge_config=$(echo "$bridge_config" | jq --arg v "$linear_team" '.linearTeam = $v')
  [[ -n "$ado_org" ]] && bridge_config=$(echo "$bridge_config" | jq --arg v "$ado_org" '.adoOrg = $v')
  [[ -n "$ado_project" ]] && bridge_config=$(echo "$bridge_config" | jq --arg v "$ado_project" '.adoProject = $v')

  echo "$existing" | jq --argjson tb "$bridge_config" '.ticketBridge = $tb' > "$settings"
  echo "Config written to ${settings}"
}

# --- main ---

case "${1:-}" in
  detect)   shift; detect_tickets "$@" ;;
  format-pr) shift; format_pr "$@" ;;
  config)   shift; config_cmd "$@" ;;
  --help|-h) usage ;;
  *)        usage; exit 1 ;;
esac
