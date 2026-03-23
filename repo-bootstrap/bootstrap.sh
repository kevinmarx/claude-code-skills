#!/usr/bin/env bash
set -euo pipefail

# repo-bootstrap: detect project type, check health, install deps

REPO_PATH="."
JSON_OUTPUT=false
ACTION=""
AUTO_YES=false

usage() {
  cat <<EOF
Usage: bootstrap.sh <command> [options]

Commands:
  status              Detect project type and report health
  install [--yes]     Run the right install command for this project

Options:
  --path <dir>        Target directory (default: current directory)
  --json              Output status as JSON
  --yes               Skip confirmation for install
  --help              Show this help
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    status)  ACTION="status"; shift ;;
    install) ACTION="install"; shift ;;
    --path)  REPO_PATH="${2:?Error: --path requires a directory}"; shift 2 ;;
    --json)  JSON_OUTPUT=true; shift ;;
    --yes)   AUTO_YES=true; shift ;;
    --help|-h) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "$ACTION" ]] && usage

cd "$REPO_PATH"

# --- Detection helpers ---

detect_projects() {
  local types=()
  [[ -f package.json ]]      && types+=("node")
  [[ -f go.mod ]]            && types+=("go")
  [[ -f Gemfile ]]           && types+=("ruby")
  [[ -f Package.swift ]]     && types+=("swift")
  [[ -f pyproject.toml ]]    && types+=("python-pyproject")
  [[ -f requirements.txt ]]  && types+=("python-requirements")
  [[ -f Cargo.toml ]]        && types+=("rust")
  echo "${types[*]:-none}"
}

check_deps_installed() {
  local type="$1"
  case "$type" in
    node)                [[ -d node_modules ]] && echo "yes" || echo "no" ;;
    go)                  [[ -d vendor ]] && echo "yes (vendor)" || echo "maybe (module cache)" ;;
    ruby)               [[ -d vendor/bundle ]] && echo "yes" || echo "maybe (system gems)" ;;
    swift)              [[ -d .build ]] && echo "yes" || echo "no" ;;
    python-pyproject)   echo "unknown (venv check needed)" ;;
    python-requirements) echo "unknown (venv check needed)" ;;
    rust)               [[ -d target ]] && echo "yes" || echo "no" ;;
    *) echo "n/a" ;;
  esac
}

detect_node_pm() {
  if [[ -f pnpm-lock.yaml ]]; then
    echo "pnpm"
  elif [[ -f yarn.lock ]]; then
    echo "yarn"
  else
    echo "npm"
  fi
}

install_command_for() {
  local type="$1"
  case "$type" in
    node)                echo "$(detect_node_pm) install" ;;
    go)                  echo "go mod download" ;;
    ruby)               echo "bundle install" ;;
    swift)              echo "swift build" ;;
    python-pyproject)   echo "pip install -e ." ;;
    python-requirements) echo "pip install -r requirements.txt" ;;
    rust)               echo "cargo build" ;;
    *) echo "" ;;
  esac
}

git_status() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "not a git repo"
    return
  fi

  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "detached")

  local ahead_behind=""
  if git rev-parse --abbrev-ref '@{upstream}' &>/dev/null 2>&1; then
    local ahead behind
    ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
    behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
    ahead_behind="ahead:${ahead} behind:${behind}"
  else
    ahead_behind="no upstream"
  fi

  local dirty="clean"
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    dirty="dirty"
  fi

  echo "${branch} | ${ahead_behind} | ${dirty}"
}

# --- Commands ---

cmd_status() {
  local types
  types=$(detect_projects)
  local has_claude_md="no"
  [[ -f .claude/CLAUDE.md ]] && has_claude_md="yes"
  local git_info
  git_info=$(git_status)

  if [[ "$JSON_OUTPUT" == true ]]; then
    local deps_json="{"
    local first=true
    for t in $types; do
      local dep_status
      dep_status=$(check_deps_installed "$t")
      if [[ "$first" == true ]]; then
        first=false
      else
        deps_json+=","
      fi
      deps_json+="\"${t}\":\"${dep_status}\""
    done
    deps_json+="}"

    cat <<EOF
{"path":"$(pwd)","project_types":"${types}","deps_installed":${deps_json},"git":"${git_info}","claude_md":"${has_claude_md}"}
EOF
  else
    echo "repo: $(basename "$(pwd)")"
    echo "path: $(pwd)"
    echo "type: ${types}"
    if [[ "$types" != "none" ]]; then
      for t in $types; do
        echo "deps (${t}): $(check_deps_installed "$t")"
      done
    fi
    echo "git: ${git_info}"
    echo "CLAUDE.md: ${has_claude_md}"
  fi
}

cmd_install() {
  local types
  types=$(detect_projects)

  if [[ "$types" == "none" ]]; then
    echo "No recognized project files found."
    exit 1
  fi

  for t in $types; do
    local cmd
    cmd=$(install_command_for "$t")
    if [[ -z "$cmd" ]]; then
      continue
    fi

    if [[ "$AUTO_YES" == true ]]; then
      echo "Running: ${cmd}"
      $cmd
    else
      echo "Would run: ${cmd}"
      read -rp "Proceed? [y/N] " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        $cmd
      else
        echo "Skipped."
      fi
    fi
  done
}

case "$ACTION" in
  status)  cmd_status ;;
  install) cmd_install ;;
esac
