# Target class for the "method probe, code loaded AFTER implicit
# enablement" case in probe_coverage_spec.rb (test 22).
#
# Method probes use Module#prepend, so they're insensitive to
# code-tracking timing — this case is regression coverage. Distinct
# fixture per matrix cell. See probe_coverage_line_pre_target_class.rb
# for the per-case-fixture rationale.
class ProbeCoverageMethodPostTargetClass
  def target_method
    42
  end
end
