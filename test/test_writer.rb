require 'minitest'
require 'minitest/autorun'

class TraceBufferTest < Minitest::Test

  def test_trace_buffer_max_size()
    buffer = Datadog::TraceBuffer.new(3)
    buffer.push(1)
    buffer.push(2)
    buffer.push(3)
    buffer.push(4)
    out = buffer.pop()
    assert_equal(out.length, 3)
    assert out.include?(4)
  end

  def test_trace_buffer()
    buffer = Datadog::TraceBuffer.new(500)

    thread_count = 100

    threads = thread_count.times.map do |i|
      Thread.new {
        sleep(rand()/1000)
        buffer.push(i)
      }
    end
    threads.each{|t| t.join()}
    out = buffer.pop()
    assert !out.nil?
    expected = (0..thread_count-1).to_a
    assert_equal(out.sort, expected)
  end

end

