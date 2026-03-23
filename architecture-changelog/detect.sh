#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: detect.sh [--staged] [--commits N] [--path <dir>]

Detect architectural changes in git diffs.

Options:
  --staged       Scan staged changes (default)
  --commits N    Scan the last N commits
  --path <dir>   Target repository directory
  --help         Show this help

Output: JSON array of {"category":"...", "file":"...", "detail":"..."}
EOF
  exit 0
}

MODE="staged"
COMMITS=""
REPO_PATH="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged)  MODE="staged"; shift ;;
    --commits) MODE="commits"; COMMITS="${2:?Error: --commits requires a number}"; shift 2 ;;
    --path)    REPO_PATH="${2:?Error: --path requires a directory}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

cd "$REPO_PATH"

if [[ "$MODE" == "commits" ]]; then
  FILES=$(git diff "HEAD~${COMMITS}" --name-only 2>/dev/null || true)
else
  FILES=$(git diff --cached --name-only 2>/dev/null || true)
fi

if [[ -z "$FILES" ]]; then
  echo "[]"
  exit 0
fi

RESULTS=()

add_result() {
  local category="$1" file="$2" detail="$3"
  RESULTS+=("{\"category\":\"${category}\",\"file\":\"${file}\",\"detail\":\"${detail}\"}")
}

while IFS= read -r file; do
  base=$(basename "$file")

  # dependencies
  case "$base" in
    package.json)
      add_result "dependencies" "$file" "Node.js dependencies" ;;
    go.mod|go.sum)
      add_result "dependencies" "$file" "Go module dependencies" ;;
    Gemfile|Gemfile.lock)
      add_result "dependencies" "$file" "Ruby gem dependencies" ;;
    Podfile|Podfile.lock)
      add_result "dependencies" "$file" "CocoaPods dependencies" ;;
    requirements.txt)
      add_result "dependencies" "$file" "Python pip dependencies" ;;
    pyproject.toml)
      add_result "dependencies" "$file" "Python project dependencies" ;;
    Cargo.toml)
      add_result "dependencies" "$file" "Rust crate dependencies" ;;
  esac

  # config
  case "$base" in
    tsconfig*.json)
      add_result "config" "$file" "TypeScript compiler config" ;;
    jest.config.*|vitest.config.*)
      add_result "config" "$file" "Test runner config" ;;
    .eslintrc*|eslint.config.*)
      add_result "config" "$file" "Linter config" ;;
    .prettierrc*|prettier.config.*)
      add_result "config" "$file" "Formatter config" ;;
    drizzle.config.*)
      add_result "config" "$file" "Drizzle ORM config" ;;
    docker-compose*|Dockerfile*)
      add_result "config" "$file" "Container config" ;;
    Makefile|Rakefile)
      add_result "config" "$file" "Build system config" ;;
    .env.example)
      add_result "config" "$file" "Environment variable template" ;;
  esac

  # ci
  case "$file" in
    .github/workflows/*)
      add_result "ci" "$file" "GitHub Actions workflow" ;;
    azure-pipelines.yml|azure-pipelines.yaml)
      add_result "ci" "$file" "Azure Pipelines config" ;;
    .gitlab-ci.yml|.gitlab-ci.yaml)
      add_result "ci" "$file" "GitLab CI config" ;;
    Jenkinsfile)
      add_result "ci" "$file" "Jenkins pipeline" ;;
  esac

  # testing (match on path components)
  case "$file" in
    *__tests__/*|*/spec/*|*/test/*|*/tests/*)
      add_result "testing" "$file" "Test file" ;;
  esac
  case "$base" in
    jest.config.*|vitest.config.*)
      add_result "testing" "$file" "Test runner config" ;;
    .rspec)
      add_result "testing" "$file" "RSpec config" ;;
    pytest.ini)
      add_result "testing" "$file" "Pytest config" ;;
  esac

  # database
  case "$file" in
    */migrations/*|*/migrate/*|*/drizzle/*|*/prisma/migrations/*|*/db/migrate/*)
      add_result "database" "$file" "Database migration" ;;
    schema.prisma)
      add_result "database" "$file" "Prisma schema" ;;
  esac

done <<< "$FILES"

# Deduplicate results (portable, no associative arrays)
if [[ ${#RESULTS[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

UNIQUE=()
for entry in "${RESULTS[@]}"; do
  dup=0
  if [[ ${#UNIQUE[@]} -gt 0 ]]; then
    for existing in "${UNIQUE[@]}"; do
      if [[ "$entry" == "$existing" ]]; then
        dup=1
        break
      fi
    done
  fi
  if [[ $dup -eq 0 ]]; then
    UNIQUE+=("$entry")
  fi
done

if [[ ${#UNIQUE[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Build JSON output
if command -v jq &>/dev/null; then
  printf '%s\n' "${UNIQUE[@]}" | jq -s '.'
else
  echo "["
  last=$(( ${#UNIQUE[@]} - 1 ))
  for i in "${!UNIQUE[@]}"; do
    if [[ $i -lt $last ]]; then
      printf '  %s,\n' "${UNIQUE[$i]}"
    else
      printf '  %s\n' "${UNIQUE[$i]}"
    fi
  done
  echo "]"
fi
