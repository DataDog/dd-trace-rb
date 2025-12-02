#!/bin/bash

set -e

CI=$1
MONOTONIC_ID=$2
GIT_REF=$3
GIT_COMMIT_SHA=$4

if test -z "$CI" || test -z "$MONOTONIC_ID" || test -z "$GIT_REF" || test -z "$GIT_COMMIT_SHA"; then
  echo Some required variables are missing - this script is meant to run in a CI enviroment 1>&2
  exit 1
fi

echo CI=$CI
echo MONOTONIC_ID=$MONOTONIC_ID
echo GIT_REF=$GIT_REF
echo GIT_COMMIT_SHA=$GIT_COMMIT_SHA

git_branch="${GIT_REF#refs/heads/}"
echo git_branch="${git_branch}"

git_branch_hash=$(echo "$git_branch" | ruby -rdigest -n -e 'print Digest::SHA256.hexdigest($_.chomp)[0, 6]')
echo git_branch_hash="${git_branch_hash}"

git_short_sha=${GIT_COMMIT_SHA:0:8}
echo git_short_sha=$git_short_sha

PRE=dev
echo PRE="${PRE}"

# Set component values:
# - PRE is `dev` to denote being a development version and
#   act as a categorizer.
# - BUILD starts with git branch sha for grouping, prefixed by `b`.
# - BUILD has CI run id for traceability, prefixed by `gha` or `glci`
#   for identification.
# - BUILD has commit next for traceability, prefixed git-describe
#   style by `g` for identification.
BUILD="b${git_branch_hash}.${CI}${MONOTONIC_ID}.g${git_short_sha}"
echo BUILD="${BUILD}"

# Patch in components
sed lib/datadog/version.rb -i -e  "s/^\([\t ]*PRE\) *= */\1 = \'${PRE}\' # /"
sed lib/datadog/version.rb -i -e  "s/^\([\t ]*BUILD\) *= */\1 = \'${BUILD}\' # /"

# Test result
cat lib/datadog/version.rb | grep -e PRE -e BUILD

ruby -Ilib -rdatadog/version -e 'puts Datadog::VERSION::STRING'
ruby -Ilib -rdatadog/version -e 'puts Gem::Version.new(Datadog::VERSION::STRING).to_s'
