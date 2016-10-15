require 'helper'
require 'ddtrace'

class TracerTest < Minitest::Test
  def test_default_tracer
    assert Datadog.tracer.instance_of?(Datadog::Tracer)
  end
end
