#!/bin/bash

echo CI_JOB_ID="${CI_JOB_ID}"

git_ref="${CI_COMMIT_REF_NAME}"
echo git_ref="${git_ref}"

git_branch="$(echo "${git_ref}" | sed -e 's#^refs/heads/##')"
echo git_branch="${git_branch}"

git_branch_hash=$(echo "$git_branch" | ruby -rdigest -n -e 'print Digest::SHA256.hexdigest($_.chomp)[0, 6]')
echo git_branch_hash="${git_branch_hash}"

git_sha=$(git rev-parse --short=8 HEAD)
echo git_sha="${git_sha}"

PRE='dev'
echo PRE="${PRE}"

BUILD="b${git_branch_hash}.glci${CI_JOB_ID}.g${git_sha}"
echo BUILD="${BUILD}"

# Patch in components
sed lib/ddtrace/version.rb -i -e  "s/^\([\t ]*PRE\) *= */\1 = \'${PRE}\' # /"
sed lib/ddtrace/version.rb -i -e  "s/^\([\t ]*BUILD\) *= */\1 = \'${BUILD}\' # /"

# Test result
cat lib/ddtrace/version.rb | grep -e PRE -e BUILD

ruby -Ilib -rddtrace/version -e 'puts DDTrace::VERSION::STRING'
ruby -Ilib -rddtrace/version -e 'puts Gem::Version.new(DDTrace::VERSION::STRING).to_s'
