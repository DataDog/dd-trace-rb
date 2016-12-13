require 'minitest'
require 'minitest/autorun'
require 'elasticsearch/transport'
require 'redis'

# AutopatchTest checks that autopatching works when using the
# env var DATADOG_TRACE_AUTOPATCH is set to true (the 'true' string).
# This env var ^ MUST BE SET for the test to pass.
class AutopatchTest < Minitest::Test
  def test_autopatch
    require 'ddtrace/monkey'
    patched_modules = Datadog::Monkey.get_patched_modules
    assert_equal(false, patched_modules[:elasticsearch])
    assert_equal(false, patched_modules[:redis])
    ENV['DATADOG_TRACE_AUTOPATCH'] = 'true'
    # Note, when using autopatching, requirements order does matter,
    # you need to import 3rd party libs *before* ddtrace.
    require 'ddtrace'
    patched_modules = Datadog::Monkey.get_patched_modules
    assert_equal(true, patched_modules[:elasticsearch])
    assert_equal(true, patched_modules[:redis])
  end
end
