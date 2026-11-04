#!/bin/bash
# Downloads the raw timing artifacts uploaded by Unit Tests batch jobs.
#
# Contract:
#   Input:  GH_TOKEN (read access to GITHUB_REPOSITORY)
#           $1 target directory
#           $2 branch carrying successful Unit Tests push runs (default: master)
#   Output: $1 populated with one subdirectory per run. Each holds one
#           subdirectory per downloaded timings artifact.
#   Failure: nonzero exit when gh fails. A partial directory is left behind.

set -euo pipefail

directory="${1:?target directory required}"
branch="${2:-master}"
response="$(gh api --method GET "repos/${GITHUB_REPOSITORY}/actions/workflows/test.yml/runs" \
  -f branch="${branch}" -f event=push -f status=success -F per_page=5)"
run_ids="$(jq -r --arg repo "${GITHUB_REPOSITORY}" --arg branch "${branch}" '
  .workflow_runs[] |
  select(.event == "push" and .conclusion == "success" and
    .path == ".github/workflows/test.yml" and .head_branch == $branch and
    .repository.full_name == $repo and .head_repository.full_name == $repo) |
  .id' <<< "${response}")"

for run_id in ${run_ids}; do
  gh run download "${run_id}" --repo "${GITHUB_REPOSITORY}" --pattern 'timings-*' --dir "${directory}/${run_id}"
done
