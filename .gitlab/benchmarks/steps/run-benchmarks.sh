#!/usr/bin/env bash

set -ex

# -- Candidate release

CANDIDATE_SRC="/app/candidate/"
CANDIDATE_BRANCH=$UPSTREAM_BRANCH
CANDIDATE_COMMIT_SHA=$UPSTREAM_COMMIT_SHA

# Clone your candidate release
git clone --branch $CANDIDATE_BRANCH https://github.com/DataDog/dd-trace-rb/ "$CANDIDATE_SRC" && \
  cd "$CANDIDATE_SRC" && \
  git checkout $CANDIDATE_COMMIT_SHA

# Run benchmarks for candidate release
cd "$CANDIDATE_SRC"
bundle install
bundle exec rake compile

benchmarks/run_all.sh

# Save results to artifacts directory
mkdir "$ARTIFACTS_DIR/candidate"
cp *-results.json "$ARTIFACTS_DIR/candidate" || cp benchmarks/*-results.json "$ARTIFACTS_DIR/candidate"

# -- Baseline release

BASELINE_SRC="/app/baseline/"
BASELINE_BRANCH=$(github-find-merge-into-branch --for-repo="$UPSTREAM_PROJECT_NAME" --for-pr="$UPSTREAM_BRANCH" || :)

if [ ! -z "$BASELINE_BRANCH" ]; then
  cd "$CANDIDATE_SRC"
  BASELINE_COMMIT_SHA=$(git merge-base origin/$BASELINE_BRANCH origin/$CANDIDATE_BRANCH)

  # Clone your baseline release
  git clone --branch $BASELINE_BRANCH https://github.com/DataDog/dd-trace-rb/ "$BASELINE_SRC" && \
    cd "$BASELINE_SRC" && \
    git checkout $BASELINE_COMMIT_SHA

  # Run benchmarks for baseline release
  cd "$BASELINE_SRC"
  bundle install
  bundle exec rake compile

  # Ensure baseline runs the same benchmarks as candidate
  cp -r $CANDIDATE_SRC/benchmarks/* "$BASELINE_SRC/benchmarks/"

  benchmarks/run_all.sh

  # Save results to artifacts directory
  mkdir "$ARTIFACTS_DIR/baseline"
  cp *-results.json "$ARTIFACTS_DIR/baseline" || cp benchmarks/*-results.json "$ARTIFACTS_DIR/baseline"
fi
