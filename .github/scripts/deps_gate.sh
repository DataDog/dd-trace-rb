#!/usr/bin/env bash
#
# Dependency gate decision (see .github/workflows/_deps_gate.yml).
#
# Runs only when dependency files changed. Probes every base gemfile against its
# lockfile and emits proceed=true|false to "$GITHUB_OUTPUT":
#   true  - every lockfile is consistent with its gemfile; dependent (expensive)
#           jobs may run.
#   false - at least one lockfile is stale; dependent jobs should skip and wait
#           for the lock-dependency bot to regenerate and commit the lockfiles,
#           which re-triggers CI on a fresh commit.
#
# All base gemfiles are probed (not just one) so that a change isolated to a
# single Ruby's gemfile, or a broad change (gemspec, appraisal) that affects
# every lockfile, is caught.
set -uo pipefail

export BUNDLE_FROZEN=true
proceed=true

for gemfile in gemfiles/ruby-*.gemfile; do
  rc=0
  BUNDLE_GEMFILE="$gemfile" ruby .github/scripts/deps_gate_probe.rb || rc=$?
  case "$rc" in
    0)
      ;;
    2)
      echo "::notice::Stale lockfile for ${gemfile}; waiting for the lock-dependency bot."
      proceed=false
      ;;
    *)
      echo "::error::deps-gate probe errored for ${gemfile} (exit ${rc})."
      exit 1
      ;;
  esac
done

echo "Dependency files changed; all lockfiles consistent: ${proceed}."
echo "proceed=${proceed}" >> "$GITHUB_OUTPUT"
