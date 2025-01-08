# Overlay patch fix for https://github.com/simplecov-ruby/simplecov/pull/972.
#
# simplecov supports branch coverage only on some Ruby runtimes (for example,
# not on JRuby). However, when merging coverage reports across runs,
# simplecov assumes that branch coverage is always present.
# This causes merging to fail when the runs are on different Ruby runtimes
# as well as when merging on JRuby.
#
# Upstream has not fixed the issue in 3+ years (PR opened in 2021).
#
# dd-trace-rb has been using a fork of simplecov with this fix, however
# this is awkward because bundler insists on constantly installing the fork
# even though nothing in it or related to it changed.
#
# This file now brings the patch into our tree, permitting us to use any
# released version of simplecov and removing the need to reference a fork.

module SimpleCovCombineFix
  def combine(coverage_a, coverage_b)
    super.tap do |result|
      result['branches'] ||= {} if SimpleCov.branch_coverage?
    end
  end
end

class << SimpleCov::Combine::FilesCombiner
  prepend(SimpleCovCombineFix)
end
