#!/usr/bin/env bash
set -euo pipefail

# Prints the result of comparing the tree of the commit named by the first
# argument with the staged tree: match, mismatch, or unreadable when the
# commit's tree cannot be read after three attempts. Reads GH_TOKEN and REPO
# from the environment.

commit_sha="$1"
commit_tree=""
for _ in 1 2 3; do
  if commit_tree="$(gh api "repos/$REPO/git/commits/$commit_sha" --jq .tree.sha)"; then
    break
  fi
  sleep 10
done
if [ -z "$commit_tree" ]; then
  echo "Could not read the commit's tree after three attempts." >&2
  echo unreadable
  exit 0
fi

staged_tree="$(git write-tree)"
if [ "$commit_tree" = "$staged_tree" ]; then
  echo match
else
  echo "The commit does not contain the staged changes." >&2
  echo mismatch
fi
