#!/bin/bash
# Runs the standalone dependency audit exactly like CI: installs the gems
# the task needs outside the bundle, then invokes it via `rake -f` so the
# full Rakefile (and its gem requirements) is never loaded.
set -euo pipefail

gem install --no-document rake:13.4.2 bundler-audit:0.9.3 terminal-table:4.0.0
rake -f tasks/dependency_audit.rake dependency:audit
