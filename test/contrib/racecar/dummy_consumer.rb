require 'racecar'

class DummyConsumer < Racecar::Consumer
  subscribes_to "dd_trace_test_dummy"

  def process(message)
    raise ArgumentError.new('Failure is not an option!') if message.value == 'fail'
  end
end
