#!/usr/bin/env bash

set -ex

# Benchmark analyzer config

# @ivoanjo As of August 2024 the current set of Ruby microbenchmarks have proven to have some instability and so
# we decided to raise the threshold to 5%. Ideally this should be balanced with work to make sure the benchmarks
# become more repeatable over time, see
# https://datadoghq.atlassian.net/wiki/spaces/APMINT/pages/3973906522/Checklist+for+New+Microbenchmarks for reference.
export UNCONFIDENCE_THRESHOLD=5.0  # Don’t report regressions smaller than this %
export DISABLE_NHST=1
export CI_TYPE=theoretical
export MD_REPORT_ONLY_CHANGES=1

CPU_MODEL=$(cat "$ARTIFACTS_DIR/lscpu.txt" | grep -Eo 'Model name: .*' | sed 's/Model name://' | awk '{$1=$1;print}')
CI_JOB_DATE=$(date +%s)

if [ -z "$CPU_MODEL" ]; then
  echo "FAIL! Failed to extract CPU_MODEL from lscpu.txt"
  exit 1
fi

KERNEL_VERSION=$(uname -a || echo "Unknown")

# -- Analyze candidate branch results

CANDIDATE_BRANCH=$UPSTREAM_BRANCH
CANDIDATE_SRC="/app/candidate/"
CANDIDATE_RESULTS="$ARTIFACTS_DIR/candidate/*-results.json"

# Get commit SHA for candidate branch
cd "$CANDIDATE_SRC"
CANDIDATE_COMMIT_SHA=$(git rev-parse HEAD)
CANDIDATE_COMMIT_DATE=$(git show -s --format=%ct $CANDIDATE_COMMIT_SHA)

benchmark_analyzer convert \
  --extra-params="{\
  \"config\":\"candidate\", \
  \"cpu_model\":\"$CPU_MODEL\", \
  \"kernel_version\":\"$KERNEL_VERSION\", \
  \"ci_job_date\":\"$CI_JOB_DATE\", \
  \"ci_job_id\":\"$CI_JOB_ID\", \
  \"ci_pipeline_id\":\"$CI_PIPELINE_ID\", \
  \"git_commit_sha\":\"$CANDIDATE_COMMIT_SHA\", \
  \"git_commit_date\":\"$CANDIDATE_COMMIT_DATE\", \
  \"git_branch\":\"$CANDIDATE_BRANCH\"\
  }" \
  --framework=BenchmarkIps \
  --outpath="$ARTIFACTS_DIR/candidate.converted.json" \
  $CANDIDATE_RESULTS

benchmark_analyzer analyze \
  --format=md \
  --outpath="$ARTIFACTS_DIR/candidate-analysis.md" \
 "$ARTIFACTS_DIR/candidate.converted.json"


# -- Analyze baseline branch results

BASELINE_SRC="/app/baseline/"
if [ -d $BASELINE_SRC ]; then
  BASELINE_BRANCH=$(github-find-merge-into-branch --for-repo="$UPSTREAM_PROJECT_NAME" --for-pr="$UPSTREAM_BRANCH" || :)
  BASELINE_RESULTS="$ARTIFACTS_DIR/baseline/*-results.json"

  # Get commit SHA for baseline branch
  cd "$BASELINE_SRC"
  BASELINE_COMMIT_SHA=$(git rev-parse HEAD)
  BASELINE_COMMIT_DATE=$(git show -s --format=%ct $BASELINE_COMMIT_SHA)

  benchmark_analyzer convert \
    --extra-params="{\
    \"config\":\"baseline\", \
    \"cpu_model\":\"$CPU_MODEL\", \
    \"kernel_version\":\"$KERNEL_VERSION\", \
    \"ci_job_date\":\"$CI_JOB_DATE\", \
    \"ci_job_id\":\"$CI_JOB_ID\", \
    \"ci_pipeline_id\":\"$CI_PIPELINE_ID\", \
    \"git_commit_sha\":\"$BASELINE_COMMIT_SHA\", \
    \"git_commit_date\":\"$BASELINE_COMMIT_DATE\", \
    \"git_branch\":\"$BASELINE_BRANCH\"\
    }" \
    --framework=BenchmarkIps \
    --outpath="$ARTIFACTS_DIR/baseline.converted.json" \
    $BASELINE_RESULTS

  benchmark_analyzer analyze \
    --format=md \
    --outpath="$ARTIFACTS_DIR/baseline-analysis.md" \
   "$ARTIFACTS_DIR/baseline.converted.json"
fi


# -- Compare results between baseline and candidate branches

if [ -d $BASELINE_SRC ]; then
  benchmark_analyzer compare pairwise \
    --baseline='{"config":"baseline"}' \
    --candidate='{"config":"candidate"}' \
    --format=md-nodejs \
    --outpath="$ARTIFACTS_DIR/comparison-baseline-vs-candidate.md" \
   "$ARTIFACTS_DIR/baseline.converted.json" "$ARTIFACTS_DIR/candidate.converted.json"
fi
