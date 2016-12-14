require 'minitest'
require 'minitest/autorun'
require 'elasticsearch/transport'
require 'redis'

# AutopatchTest checks that autopatching works when using the
# env var DATADOG_TRACE_AUTOPATCH is set to true (the 'true' string).
class AutopatchTest < Minitest::Test
  def test_autopatch
    # Importing 'ddtrace/monkey' for the sake of testing and access
    # the list of patched modules, but you don't need this in the real world.
    require 'ddtrace/monkey'
    patched_modules = Datadog::Monkey.get_patched_modules
    assert_equal(false, patched_modules[:elasticsearch])
    assert_equal(false, patched_modules[:redis])

    ENV['DATADOG_TRACE_AUTOPATCH'] = 'true'
    # When using autopatching, requirements order does matter,
    # you need to import 3rd party libs *before* ddtrace.
    require 'ddtrace' # here, patching happens
    patched_modules = Datadog::Monkey.get_patched_modules
    assert_equal(true, patched_modules[:elasticsearch])
    assert_equal(true, patched_modules[:redis])
  end
end
