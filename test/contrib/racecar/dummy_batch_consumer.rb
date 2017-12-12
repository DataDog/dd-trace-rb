require 'racecar'

class DummyBatchConsumer < Racecar::Consumer
  subscribes_to "dd_trace_test_dummy_batch"

  def process_batch(batch)
    raise ArgumentError.new('Failure is not an option!') if batch.messages.any? { |m| m.value == 'fail' }
  end
end
