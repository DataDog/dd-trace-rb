#!/bin/bash
# Runs the simple-english document lint exactly like CI: installs the pinned
# linter gem and checks the standalone docs that follow its rules. Also runs
# the curl safety check (see curl_safety_check.sh) here rather than as its
# own workflow job, since this script already runs in a required, merge-
# blocking job and both checks are cheap, dependency-free static checks over
# the PR diff.
set -euo pipefail

gem install --no-document simple_english:0.6.0 # MANUAL-PIN: simple_english
se docs/DependencyAudit.md

"$(dirname "$0")/curl_safety_check.sh"
