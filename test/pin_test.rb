require 'helper'
require 'ddtrace'
require 'ddtrace/pin'
require 'ddtrace/tracer'

class PinTest < Minitest::Test
  def test_pin
    a = ""
    pin = Datadog::Pin.new(service="abc")
    assert_equal("abc", pin.service)
    pin.onto(a)

    #got = Datadog::Pin.get_from(a)
    #assert_equal("abc", got)
  end
end
