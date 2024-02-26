#!/bin/bash

# Obtain context information
git_sha=$(git rev-parse --short HEAD)

# Output info for CI debug
echo git_sha="${git_sha}"

PRE='dev'
BUILD="${git_sha}"

# Output info for CI debug
echo PRE="${PRE}"
echo BUILD="${BUILD}"

# Patch in components
sed lib/ddtrace/version.rb -i -e  "s/^\([\t ]*PRE\) *= */\1 = \'${PRE}\' # /"
sed lib/ddtrace/version.rb -i -e  "s/^\([\t ]*BUILD\) *= */\1 = \'${BUILD}\' # /"

# Test result
cat lib/ddtrace/version.rb | grep -e PRE -e BUILD

ruby -Ilib -rddtrace/version -e 'puts DDTrace::VERSION::STRING'
ruby -Ilib -rddtrace/version -e 'puts Gem::Version.new(DDTrace::VERSION::STRING).to_s'
