#!/bin/bash
# Runs the simple-english document lint exactly like CI: installs the pinned
# linter gem into a throwaway GEM_HOME (the runner's system gem dir is not
# writable) and checks the standalone docs that follow its rules.
set -euo pipefail

GEM_HOME="$(mktemp -d)"
export GEM_HOME
gem install --no-document simple_english:0.6.0
export PATH="$GEM_HOME/bin:$PATH"
se docs/DependencyAudit.md
