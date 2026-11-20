#!/usr/bin/env bash
set -euo pipefail

# Re-reads the scratch ref's head after the backoff and records the result in
# $GITHUB_OUTPUT: head-sha always; applied-hash when the commit at the head is
# verified to match the staged tree; candidate-sha when the commit may be one
# the failed attempt applied but its tree cannot be read. Reads GH_TOKEN, REPO,
# SCRATCH, GUARDED_SHA, CANDIDATE_SHA and ACTION_PATH from the environment and
# exits 1 when the head re-read fails.

sleep 30
head_sha=""
for _ in 1 2 3; do
  if head_sha="$(gh api "repos/$REPO/git/refs/heads/$SCRATCH" --jq .object.sha)"; then
    break
  fi
  sleep 10
done
if [ -z "$head_sha" ]; then
  echo "Could not re-read the scratch head after three attempts." >&2
  exit 1
fi
echo "head-sha=$head_sha" >> "$GITHUB_OUTPUT"
record_head_commit_verdict() {
  verdict="$("$ACTION_PATH/verify-commit-tree.sh" "$head_sha")"
  if [ "$verdict" = "match" ]; then
    echo "The failed attempt applied the mutation as $head_sha; using that commit."
    echo "applied-hash=$head_sha" >> "$GITHUB_OUTPUT"
  elif [ "$verdict" = "unreadable" ]; then
    echo "Recording $head_sha as an unverified candidate."
    echo "candidate-sha=$head_sha" >> "$GITHUB_OUTPUT"
  fi
}
if [ "$head_sha" != "$GUARDED_SHA" ]; then
  record_head_commit_verdict
elif [ -n "$CANDIDATE_SHA" ] && [ "$head_sha" = "$CANDIDATE_SHA" ]; then
  record_head_commit_verdict
fi
