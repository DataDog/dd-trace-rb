# frozen_string_literal: true

# Line-probe instrumentation target for the correlation integration specs.
# The class is uniquely named for the line-probe context, which loads this
# file inside its with_code_tracking around hook so the line probe resolves
# this file's iseq while code tracking is active; loading the file at spec
# load time would leave the iseq untracked, and reloading it through
# remove_const would leak the stale class and its iseqs into the object
# space beside the reloaded definition. The comment-anchored line numbers
# must stay accurate for the line-probe example, which targets line 18.
class CorrelationLineProbeTestClass
  def loop_n(n)
    n.times { inner } # line 13
    n
  end

  def inner
    42 # line 18
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 24
  raise "Wrong number of lines in correlation_line_probe_test_class.rb: actual #{actual}, expected 24"
end
