#!/bin/bash
set -euo pipefail

# Guards against pinning .github/workflows/system-tests.yml to a DataDog/system-tests
# commit that hasn't actually been merged to its default branch yet.
#
# This happened in practice: a contributor edited the `uses:`/`ref:` pins in
# system-tests.yml by hand to point at a branch commit on DataDog/system-tests
# that was still under review. Because the commit was unmerged, every dd-trace-rb
# PR's System Tests workflow broke the moment that upstream branch was rebased
# or closed. The intended flow is to merge the target commit on system-tests
# first, then regenerate the pins here via the "Update System Tests" GitHub
# Actions workflow (which always points at a merged commit).
#
# This check is mechanically verifiable: extract the two pinned SHAs
# (the reusable-workflow `uses:@<sha>` and the `with: ref:` value) and confirm,
# via the GitHub API, that each commit is reachable from the configured
# DataDog/system-tests default branch (i.e., already merged).

TARGET=".github/workflows/system-tests.yml"
SYSTEM_TESTS_REPO="DataDog/system-tests"

if [[ ! -f "${TARGET}" ]]; then
  echo "Error: ${TARGET} not found"
  exit 1
fi

uses_sha=$(grep -oE 'DataDog/system-tests/\.github/workflows/system-tests\.yml@[0-9a-f]{40}' "${TARGET}" | head -1 | sed -E 's/.*@//')
ref_sha=$(grep -E '^\s*ref:\s*[0-9a-f]{40}' "${TARGET}" | head -1 | grep -oE '[0-9a-f]{40}')

if [[ -z "${uses_sha}" || -z "${ref_sha}" ]]; then
  echo "Error: could not find both the reusable-workflow uses:@<sha> pin and the ref: pin in ${TARGET}"
  exit 1
fi

if [[ "${uses_sha}" != "${ref_sha}" ]]; then
  echo "::error file=${TARGET}::The uses:@${uses_sha} pin and the ref: ${ref_sha} pin must match. The 'Update System Tests' workflow always keeps these in sync; a mismatch means one of them was hand-edited."
  exit 1
fi

sha="${uses_sha}"
echo "Checking that ${SYSTEM_TESTS_REPO}@${sha} is merged..."

default_branch=$(curl -sS --fail --retry 3 --retry-delay 5 \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${SYSTEM_TESTS_REPO}" | jq -r '.default_branch')

if [[ -z "${default_branch}" || "${default_branch}" == "null" ]]; then
  echo "Error: could not resolve the default branch for ${SYSTEM_TESTS_REPO}"
  exit 1
fi

compare_url="https://api.github.com/repos/${SYSTEM_TESTS_REPO}/compare/${default_branch}...${sha}"
compare=$(curl -sS --fail --retry 3 --retry-delay 5 \
  -H "Accept: application/vnd.github+json" \
  "${compare_url}")

status=$(echo "${compare}" | jq -r '.status')

# "identical" or "behind" both mean the pinned commit is already an ancestor
# of (i.e. merged into) the default branch. "ahead" or "diverged" mean it is
# not: the pin references history that the default branch does not contain.
if [[ "${status}" != "identical" && "${status}" != "behind" ]]; then
  message=$(cat <<EOF
The ${SYSTEM_TESTS_REPO} commit pinned in ${TARGET} (${sha}) is not merged into
the ${SYSTEM_TESTS_REPO} default branch (${default_branch}); comparison status
is '${status}'. Pinning an unmerged commit breaks the System Tests workflow for
every dd-trace-rb pull request as soon as that upstream branch changes. Merge
the target commit on ${SYSTEM_TESTS_REPO} first, then regenerate this pin with
the "Update System Tests" GitHub Actions workflow instead of editing it by hand.
EOF
  )
  echo "::error file=${TARGET}::${message//$'\n'/ }"
  exit 1
fi

echo "OK: ${sha} is merged into ${SYSTEM_TESTS_REPO}@${default_branch} (status: ${status})"
