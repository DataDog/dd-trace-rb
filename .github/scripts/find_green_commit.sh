#!/bin/bash

# Finds the most recent commit on a GitHub repository's default branch
# where the full CI pipeline ran and passed.
#
# "Full CI pipeline" = commit has more than MIN_STATUS_COUNT status contexts.
# Most commits only have ~5 housekeeping statuses; full pipeline runs produce
# 2000+ statuses.
#
# Usage:
#   REPO=DataDog/system-tests ./find_green_commit.sh
#
# Outputs:
#   ref=<sha> to $GITHUB_OUTPUT (for use in GitHub Actions)
#   Prints the found SHA to stdout.
#   Exits 1 if no green commit is found.
#
# Requires: gh (GitHub CLI), authenticated

set -euo pipefail

REPO="${REPO:?REPO environment variable is required (e.g. DataDog/system-tests)}"
MAX_COMMITS="${MAX_COMMITS:-20}"
MIN_STATUS_COUNT="${MIN_STATUS_COUNT:-100}"

echo "Searching last ${MAX_COMMITS} commits on ${REPO} for a green full-pipeline commit..."
echo "Minimum status count for full pipeline: ${MIN_STATUS_COUNT}"

found=""

while IFS=$'\t' read -r sha date message; do
  status_json=$(gh api "repos/${REPO}/commits/${sha}/status" --jq '"\(.state)\t\(.total_count)"')
  state=$(echo "$status_json" | cut -f1)
  total=$(echo "$status_json" | cut -f2)

  echo "  ${sha:0:7} (${date}) — ${state}, ${total} checks — ${message:0:80}"

  if [ "$total" -lt "$MIN_STATUS_COUNT" ]; then
    continue
  fi

  if [ "$state" = "success" ]; then
    found="$sha"
    break
  fi
done < <(gh api "repos/${REPO}/commits?per_page=${MAX_COMMITS}" --jq '.[] | [.sha, .commit.author.date, .commit.message | split("\n") | .[0]] | @tsv')

if [ -z "$found" ]; then
  echo "No green full-pipeline commit found in last ${MAX_COMMITS} commits."
  exit 1
fi

echo ""
echo "Found green commit: ${found}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "ref=${found}" >> "$GITHUB_OUTPUT"
fi
