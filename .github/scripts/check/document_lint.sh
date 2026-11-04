#!/bin/bash
# Runs the simple-english document lint exactly like CI: installs the pinned
# linter gem and checks the standalone docs that follow its rules.
set -euo pipefail

gem install --no-document simple_english:0.13.0 # MANUAL-PIN: simple_english
se docs/DependencyAudit.md

# Skills lint runs from their own directory so that
# .agents/skills/.simple-english.yml applies: skill instructions use
# recommendation wording that SE_MODAL_RESTRICTED forbids, so it is off there.
(cd .agents/skills && se .)
