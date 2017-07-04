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
end
