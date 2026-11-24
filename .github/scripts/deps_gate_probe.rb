# frozen_string_literal: true

# Dependency gate probe (see .github/workflows/_deps_gate.yml).
#
# Checks whether the gemfile in BUNDLE_GEMFILE is consistent with its lockfile,
# WITHOUT installing gems or touching the network: it only compares the gemfile's
# declared dependencies against the lockfile. Must run under BUNDLE_FROZEN=true,
# which is what makes Bundler raise on a divergence instead of silently updating
# the lockfile.
#
# Exit codes:
#   0 - consistent: the lockfile matches the gemfile.
#   2 - stale: the gemfile changed but the lockfile has not been regenerated yet.
#   1 - probe error (e.g. a future Bundler renamed the API): surfaced loudly so it
#       gets fixed, rather than silently gating out every dependency PR.
require "bundler"

Bundler.ui.level = "error"

begin
  Bundler.definition.ensure_equivalent_gemfile_and_lockfile
  exit 0
rescue Bundler::ProductionError, Bundler::GemfileError
  exit 2
rescue => e
  warn "deps-gate: unexpected probe failure for #{ENV["BUNDLE_GEMFILE"]}: #{e.class}: #{e.message}"
  exit 1
end
