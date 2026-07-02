#!/usr/bin/env bash
# Detects changed files under PATHS and commits them via `ghcommit`, which uses the
# GraphQL createCommitOnBranch mutation to produce a single GitHub-verified signed commit.
#
# Unlike planetscale/ghcommit-action, the expected branch HEAD sha is resolved via the API
# rather than trusting the local checkout's `git rev-parse HEAD` (which can point at a
# synthetic merge commit rather than the real branch tip, e.g. on `pull_request` triggers).
set -euo pipefail

: "${REPOSITORY:?REPOSITORY is required}"
: "${BRANCH:?BRANCH is required}"
: "${COMMIT_MESSAGE:?COMMIT_MESSAGE is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

read -r -a path_specs <<<"${PATHS:-.}"

if head_sha=$(gh api "repos/$REPOSITORY/git/ref/heads/$BRANCH" -q .object.sha 2>/dev/null); then
  echo "Branch '$BRANCH' exists at $head_sha"
else
  if [[ -z "${BASE_BRANCH:-}" ]]; then
    echo "::error::Branch '$BRANCH' does not exist on $REPOSITORY and no base-branch was given to create it from"
    exit 1
  fi
  base_sha=$(gh api "repos/$REPOSITORY/git/ref/heads/$BASE_BRANCH" -q .object.sha)
  echo "Branch '$BRANCH' does not exist; creating it from '$BASE_BRANCH' ($base_sha)"
  gh api "repos/$REPOSITORY/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$base_sha" >/dev/null
  head_sha="$base_sha"
fi

adds=()
deletes=()

while IFS= read -r -d $'\0' line; do
  index_status="${line:0:1}"
  tree_status="${line:1:1}"

  # Renamed files have status 'R' and two NUL-separated filenames: old, then new.
  if [[ "$index_status" == "R" || "$tree_status" == "R" ]]; then
    IFS= read -r -d $'\0' old_filename
    new_filename="${line:3}"
    adds+=("$new_filename")
    deletes+=("$old_filename")
    continue
  fi

  filename="${line:3}"

  # https://git-scm.com/docs/git-status
  [[ "$tree_status" =~ A|M|T || "$index_status" =~ A|M|T ]] && adds+=("$filename")
  [[ "$tree_status" == "?" && "$index_status" == "?" ]] && adds+=("$filename")
  [[ "$tree_status" =~ D || "$index_status" =~ D ]] && deletes+=("$filename")
done < <(git status -s --porcelain=v1 -z -- "${path_specs[@]}")

if [[ "${#adds[@]}" -eq 0 && "${#deletes[@]}" -eq 0 ]]; then
  echo "No changes detected under: ${path_specs[*]}"
  echo "changed=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

echo "Committing ${#adds[@]} added/modified and ${#deletes[@]} deleted file(s)"

ghcommit_args=(-r "$REPOSITORY" -b "$BRANCH" -m "$COMMIT_MESSAGE" -s "$head_sha")
ghcommit_args+=("${adds[@]/#/--add=}")
ghcommit_args+=("${deletes[@]/#/--delete=}")

output=$(ghcommit "${ghcommit_args[@]}" 2>&1) || {
  echo "$output"
  exit 1
}
echo "$output"

commit_url=$(echo "$output" | grep "Success. New commit:" | awk '{print $NF}')
commit_sha="${commit_url##*/}"

{
  echo "changed=true"
  echo "commit-sha=$commit_sha"
  echo "commit-url=$commit_url"
} >>"$GITHUB_OUTPUT"
