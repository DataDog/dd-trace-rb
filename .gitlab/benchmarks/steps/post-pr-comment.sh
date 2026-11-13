#!/usr/bin/env bash

cat "$ARTIFACTS_DIR/comparison-baseline-vs-candidate.md" | pr-commenter --for-repo="$UPSTREAM_PROJECT_NAME" --for-pr="$UPSTREAM_BRANCH" --header="Benchmarks" --on-duplicate=replace
