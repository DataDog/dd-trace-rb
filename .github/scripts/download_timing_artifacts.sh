#!/bin/bash
# Downloads the raw timing artifacts uploaded by Unit Tests batch jobs.
#
# Contract:
#   Input:  GH_TOKEN (read access to GITHUB_REPOSITORY)
#           $1 target directory
#           $2 branch carrying successful Unit Tests runs (default: master)
#   Output: $1 populated with one subdirectory per run. Each holds one
#           subdirectory per downloaded timings artifact.
#   Failure: nonzero exit when gh fails. A partial directory is left behind.

set -euo pipefail

directory="${1:?target directory required}"
branch="${2:-master}"
workflow="Unit Tests"

run_ids="$(gh run list --repo "${GITHUB_REPOSITORY}" --workflow "${workflow}" --branch "${branch}" --status success --limit 5 --json databaseId --jq '.[].databaseId')"

for run_id in ${run_ids}; do
  gh run download "${run_id}" --repo "${GITHUB_REPOSITORY}" --pattern 'timings-*' --dir "${directory}/${run_id}"
done
