#!/usr/bin/env bash
# mystatus: GitHub PR queries with account switching
# Usage: status.sh --org <org>

set -euo pipefail

CONFIG_FILE="$HOME/.claude/skills/mystatus/config.json"

# Parse args
ORG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ORG" ]]; then
  echo '{"error": "Missing --org argument"}' >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo '{"error": "Config not found at '"$CONFIG_FILE"'"}' >&2
  exit 1
fi

# Read config values
GITHUB_OWNER=$(jq -r ".orgs.\"$ORG\".githubOwner // empty" "$CONFIG_FILE")
GITHUB_ACCOUNT=$(jq -r ".orgs.\"$ORG\".githubAccount // empty" "$CONFIG_FILE")

if [[ -z "$GITHUB_OWNER" || -z "$GITHUB_ACCOUNT" ]]; then
  AVAILABLE=$(jq -r '.orgs | keys | join(", ")' "$CONFIG_FILE")
  echo "{\"error\": \"Org '$ORG' not found. Available: $AVAILABLE\"}" >&2
  exit 1
fi

# Switch gh account
gh auth switch --user "$GITHUB_ACCOUNT" 2>/dev/null || true

# PRs requesting my review
PRS_TO_REVIEW=$(gh search prs \
  --review-requested @me \
  --owner "$GITHUB_OWNER" \
  --state open \
  --json repository,number,title,author,url \
  --limit 50 2>/dev/null || echo "[]")

# My open PRs — gh search prs doesn't support reviewDecision,
# so we get the list first, then enrich each PR via gh pr view
MY_PRS_RAW=$(gh search prs \
  --author @me \
  --owner "$GITHUB_OWNER" \
  --state open \
  --json repository,number,title,url \
  --limit 50 2>/dev/null || echo "[]")

# Enrich each PR with reviewDecision and statusCheckRollup via gh pr view
MY_PRS=$(echo "$MY_PRS_RAW" | jq -c '.[]' | while read -r pr; do
  REPO=$(echo "$pr" | jq -r '.repository.nameWithOwner')
  NUM=$(echo "$pr" | jq -r '.number')
  # gh pr view gives us the fields search doesn't support
  DETAILS=$(gh pr view "$NUM" \
    --repo "$REPO" \
    --json reviewDecision,statusCheckRollup \
    2>/dev/null || echo '{}')
  echo "$pr" | jq --argjson details "$DETAILS" '. + $details'
done | jq -s '.')

# Output combined JSON
jq -n \
  --argjson review "$PRS_TO_REVIEW" \
  --argjson mine "$MY_PRS" \
  '{prs_to_review: $review, my_prs: $mine}'
