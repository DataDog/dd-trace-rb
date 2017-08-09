require 'helper'
require 'ddtrace'
require 'ddtrace/pin'
require 'ddtrace/tracer'

class CustomPinSetGet
  def datadog_pin
    @custom_attribute
  end

  def datadog_pin=(pin)
    @custom_attribute = 'The PIN is set!'
  end
end

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

  def test_pin_get_from
    a = [0, nil, self] # get_from should be callable on anything

    a.each do |x|
      assert_nil(Datadog::Pin.get_from(x))
    end
  end

  def test_to_s
    pin = Datadog::Pin.new('abc', app: 'anapp', app_type: 'db')
    assert_equal('abc', pin.service)
    assert_equal('anapp', pin.app)
    assert_equal('db', pin.app_type)
    repr = pin.to_s
    assert_equal('Pin(service:abc,app:anapp,app_type:db,name:)', repr)
  end

  def test_pin_accessor
    a = '' # using String, but really, any object should fit

    pin = Datadog::Pin.new('abc')
    pin.onto(a)

    got = a.datadog_pin
    assert_equal('abc', got.service)
  end

  def test_enabled
    pin = Datadog::Pin.new('abc')
    assert_equal(true, pin.enabled?)
  end

  def test_custom_getter_setter
    # ensures that if datadog_pin is available in the class, it will
    # be used instead of the default datadog_pin
    obj = CustomPinSetGet.new
    pin = Datadog::Pin.new('pin', app: 'app', app_type: 'db')
    pin.onto(obj)
    assert_equal('The PIN is set!', Datadog::Pin.get_from(obj))
  end
end
