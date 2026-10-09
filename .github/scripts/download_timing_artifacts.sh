#!/bin/bash
# Downloads the raw timing artifacts uploaded by Unit Tests batch jobs.
#
# Contract:
#   Input:  GH_TOKEN (read access to GITHUB_REPOSITORY)
#           $1 target directory
#           $2 branch carrying successful Unit Tests runs (default: master)
#   Output: $1 populated with one subdirectory per run, each holding the
#           "timings-*.json" files written by TestBatching::TimingFiles
#           and uploaded by .github/actions/build-test.
#   Failure: nonzero exit when gh fails; a partial directory is left behind.

set -euo pipefail

directory="${1:?target directory required}"
branch="${2:-master}"
workflow="Unit Tests"

run_ids="$(gh run list --repo "${GITHUB_REPOSITORY}" --workflow "${workflow}" --branch "${branch}" --status success --limit 5 --json databaseId --jq '.[].databaseId')"

for run_id in ${run_ids}; do
  names="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/artifacts?per_page=100" --jq '.artifacts[] | select(.name | startswith("timings-")) | select(.expired == false) | .name')"

  for name in ${names}; do
    gh run download "${run_id}" --repo "${GITHUB_REPOSITORY}" --name "${name}" --dir "${directory}/${run_id}"
  done
done
