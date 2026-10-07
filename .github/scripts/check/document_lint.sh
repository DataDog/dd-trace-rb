#!/bin/bash
# Runs the simple-english document lint exactly like CI: installs the pinned
# linter gem and checks the standalone docs that follow its rules.
set -euo pipefail

gem install --no-document simple_english:0.6.0
se docs/DependencyAudit.md
