require 'racecar'

class DummyConsumer < Racecar::Consumer
  subscribes_to "dd_trace_test_dummy"

  def process(message)
    # Do nothing
  end
end
