# Target class for the "line probe, code loaded BEFORE implicit
# enablement" case in probe_coverage_spec.rb.
#
# Loaded by exactly one example before the spec triggers implicit
# enablement, so the iseq must be recovered via backfill_registry.
# Each of the four matrix cells (line/method probe × pre/post load)
# has its own fixture file and class name to avoid remove_const-then-
# redefine — that pattern
# leaks stale Class objects with cached Module#name into ObjectSpace
# (the same CRuby behavior that PR #5872 addresses for SymDB).
class ProbeCoverageLinePreTargetClass
  def target_method
    answer = 42 # line 13 — line-probe target # standard:disable Style/RedundantAssignment
    answer
  end
end
