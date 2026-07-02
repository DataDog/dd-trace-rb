#!/usr/bin/env bash
# Cheap, non-destructive check for whether there is anything to commit under PATHS. Runs
# before any branch/PR mutation so a no-op run never force-moves the bot branch or touches an
# existing PR.
set -euo pipefail

read -r -a path_specs <<<"${PATHS:-.}"

if [[ -z "$(git status --porcelain -- "${path_specs[@]}")" ]]; then
  echo "No changes detected under: ${path_specs[*]}"
  echo "changed=false" >>"$GITHUB_OUTPUT"
else
  echo "changed=true" >>"$GITHUB_OUTPUT"
fi
