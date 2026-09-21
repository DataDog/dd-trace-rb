# Target class for the "line probe, code loaded AFTER implicit
# enablement" case in probe_coverage_spec.rb.
#
# Loaded by exactly one example, after the spec activates code tracking,
# so the iseq must be captured by the :script_compiled trace point at
# load time. See probe_coverage_line_pre_target_class.rb for the
# per-case-fixture rationale.
class ProbeCoverageLinePostTargetClass
  def target_method
    answer = 42 # line 10 — line-probe target # standard:disable Style/RedundantAssignment
    answer
  end
end
