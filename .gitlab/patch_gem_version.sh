#!/bin/bash
set -e

echo CI=$1
echo MONOTONIC_ID=$2
echo GIT_REF=$3
echo GIT_COMMIT_SHA=$4

git_branch="${3#refs/heads/}"
echo git_branch="${git_branch}"

git_branch_hash=$(echo "$git_branch" | ruby -rdigest -n -e 'print Digest::SHA256.hexdigest($_.chomp)[0, 6]')
echo git_branch_hash="${git_branch_hash}"

git_short_sha=${4:0:8}
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
BUILD="b${git_branch_hash}.${1}${2}.g${git_short_sha}"
echo BUILD="${BUILD}"

# Patch in components
sed lib/datadog/version.rb -i -e  "s/^\([\t ]*PRE\) *= */\1 = \'${PRE}\' # /"
sed lib/datadog/version.rb -i -e  "s/^\([\t ]*BUILD\) *= */\1 = \'${BUILD}\' # /"

# Test result
cat lib/datadog/version.rb | grep -e PRE -e BUILD

ruby -Ilib -rdatadog/version -e 'puts Datadog::VERSION::STRING'
ruby -Ilib -rdatadog/version -e 'puts Gem::Version.new(Datadog::VERSION::STRING).to_s'
