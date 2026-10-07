#!/bin/bash
# Runs the standalone dependency audit exactly like CI: installs the gems
# the task needs outside the bundle, then invokes it via `rake -f` so the
# full Rakefile (and its gem requirements) is never loaded.
set -euo pipefail

gem install --no-document rake bundler-audit
rake -f tasks/dependency_audit.rake dependency:audit
