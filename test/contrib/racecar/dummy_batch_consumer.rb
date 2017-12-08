require 'racecar'

class DummyBatchConsumer < Racecar::Consumer
  subscribes_to "dd_trace_test_dummy_batch"

  def process_batch(batch)
    # Do nothing
  end
end
