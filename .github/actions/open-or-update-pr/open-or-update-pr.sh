#!/usr/bin/env bash
# Finds an open PR for BRANCH -> BASE and updates its title/body/labels, or opens a new one.
set -euo pipefail

: "${REPOSITORY:?REPOSITORY is required}"
: "${BRANCH:?BRANCH is required}"
: "${BASE:?BASE is required}"
: "${TITLE:?TITLE is required}"
: "${BODY:?BODY is required}"

pr_number=$(gh pr list --repo "$REPOSITORY" --head "$BRANCH" --base "$BASE" --state open --json number -q '.[0].number // empty')

label_args=()
if [[ -n "${LABELS:-}" ]]; then
  IFS=',' read -r -a raw_labels <<<"$LABELS"
  for label in "${raw_labels[@]}"; do
    label="$(echo "$label" | xargs)"
    [[ -n "$label" ]] && label_args+=(--label "$label")
  done
fi

if [[ -n "$pr_number" ]]; then
  echo "Updating existing PR #$pr_number"
  gh pr edit "$pr_number" --repo "$REPOSITORY" --title "$TITLE" --body "$BODY" "${label_args[@]}" >/dev/null
  pr_url=$(gh pr view "$pr_number" --repo "$REPOSITORY" --json url -q .url)
else
  echo "Creating new PR for '$BRANCH' -> '$BASE'"
  pr_url=$(gh pr create --repo "$REPOSITORY" --head "$BRANCH" --base "$BASE" --title "$TITLE" --body "$BODY" "${label_args[@]}")
  pr_number=$(gh pr view "$pr_url" --repo "$REPOSITORY" --json number -q .number)
fi

{
  echo "pr-number=$pr_number"
  echo "pr-url=$pr_url"
} >>"$GITHUB_OUTPUT"
