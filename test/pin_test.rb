require 'helper'
require 'ddtrace'
require 'ddtrace/pin'
require 'ddtrace/tracer'

class PinTest < Minitest::Test
  def test_pin_onto
    a = '' # using String, but really, any object should fit

    pin = Datadog::Pin.new('abc', app: 'anapp')
    assert_equal('abc', pin.service)
    assert_equal('anapp', pin.app)
    pin.onto(a)

    got = Datadog::Pin.get_from(a)
    assert_equal('abc', got.service)
    assert_equal('anapp', got.app)
  end

  def test_pin_accessor
    a = '' # using String, but really, any object should fit

    pin = Datadog::Pin.new('abc')
    pin.onto(a)

    got = a.datadog_pin
    assert_equal('abc', got.service)
  end
end
