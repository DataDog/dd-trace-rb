#!/usr/bin/env bash
# Force-moves BRANCH (a disposable bot-owned branch) to point at the currently checked-out
# HEAD, discarding any commits left over from previous runs. The signed-commit action then
# adds a single new commit on top, so every run produces "BASE + this run's changes" rather
# than an ever-growing stack of stale commits from past runs.
#
# HEAD is used as the reset target (not a freshly re-fetched BASE tip) so that a long-running
# job (matrix builds, bundle installs) can't race a concurrent push to BASE: whatever commit
# was actually checked out is what the diff was computed against, and is what the branch is
# reset to.
set -euo pipefail

: "${REPOSITORY:?REPOSITORY is required}"
: "${BRANCH:?BRANCH is required}"
: "${BASE:?BASE is required}"

if [[ "$BRANCH" == "$BASE" ]]; then
  echo "::error::branch ('$BRANCH') must differ from base ('$BASE')"
  exit 1
fi

head_sha=$(git rev-parse HEAD)

if gh api "repos/$REPOSITORY/git/ref/heads/$BRANCH" >/dev/null 2>&1; then
  echo "Resetting existing branch '$BRANCH' to current HEAD ($head_sha)"
  gh api -X PATCH "repos/$REPOSITORY/git/refs/heads/$BRANCH" -f sha="$head_sha" -F force=true >/dev/null
else
  echo "Creating branch '$BRANCH' at current HEAD ($head_sha)"
  gh api "repos/$REPOSITORY/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$head_sha" >/dev/null
fi
