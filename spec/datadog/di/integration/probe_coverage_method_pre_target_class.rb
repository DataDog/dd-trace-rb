# Target class for the "method probe, code loaded BEFORE implicit
# enablement" case in probe_coverage_spec.rb.
#
# Method probes use Module#prepend, so they're insensitive to
# code-tracking timing — this case is regression coverage. Distinct
# fixture per matrix cell. See probe_coverage_line_pre_target_class.rb
# for the per-case-fixture rationale.
class ProbeCoverageMethodPreTargetClass
  def target_method
    42
  end
end
