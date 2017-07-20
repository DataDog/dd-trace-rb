require 'helper'

require 'minitest'
require 'minitest/autorun'

class UtilsTest < Minitest::Test
  def test_rand_multithread
    n = 100

    mutex = Mutex.new

    @numbers = {}
    threads = []
    n.times do |_i|
      thread = Thread.new do
        r = Datadog::Utils.next_id()
        mutex.synchronize do
          @numbers[r] = true
        end
      end
      mutex.synchronize do
        threads << thread
      end
    end
    threads.each(&:join)
    assert_equal(n, @numbers.length, 'each trace ID should be picked only once')
    @numbers = nil
  end

  def test_rand_no_side_effect
    tracer = get_test_tracer()

    srand 1234
    tracer.trace('random') do # this creates span, so calls our PRNG
      r1 = rand
      r2 = rand
      # Should we not use our own PRNG, the test below would fail, typically
      # r1 would be 0.6221087710398319 because its expected values has been
      # picked up already and used for the span_id & trace_id.
      assert_equal(0.1915194503788923, r1, '1st randomly generated number should not be altered by tracing')
      assert_equal(0.6221087710398319, r2, '2nd randomly generated number should not be altered by tracing')
    end
  end
end
