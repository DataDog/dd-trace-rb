require 'minitest'
require 'minitest/autorun'

class TraceBufferTest < Minitest::Test
  def test_trace_buffer_thread_safety
    # ensures that the buffer is thread safe
    thread_count = 100
    buffer = Datadog::TraceBuffer.new(500)

    threads = Array.new(thread_count) do |i|
      Thread.new do
        sleep(rand / 1000)
        buffer.push(i)
      end
    end

    threads.each(&:join)
    out = buffer.pop
    assert !out.nil?
    expected = (0..thread_count - 1).to_a
    assert_equal(out.sort, expected)
  end

  def test_trace_buffer_with_limit
    # ensures that the buffer has max size
    buffer = Datadog::TraceBuffer.new(3)
    buffer.push(1)
    buffer.push(2)
    buffer.push(3)
    buffer.push(4)
    out = buffer.pop
    assert_equal(out.length, 3)
    assert out.include?(4)
  end

  def test_trace_buffer_without_limit
    # the trace buffer has an unlimited size if created with
    # a zero (or negative) value
    buffer = Datadog::TraceBuffer.new(0)
    buffer.push(1)
    buffer.push(2)
    buffer.push(3)
    buffer.push(4)
    out = buffer.pop
    assert_equal(out.length, 4)
  end

  def test_trace_buffer_empty
    # ensures empty? works as expected
    buffer = Datadog::TraceBuffer.new(1)
    assert buffer.empty?
    buffer.push(1)
    assert !buffer.empty?
  end

  def test_trace_buffer_pop
    # the trace buffer must return all internal traces
    buffer = Datadog::TraceBuffer.new(0)
    span1 = Datadog::Span.new(nil, 'client.testing')
    span2 = Datadog::Span.new(nil, 'client.testing')
    buffer.push(span1)
    buffer.push(span2)
    # collect traces
    traces = buffer.pop()
    # the buffer must be empty
    assert buffer.empty?
    assert_equal(traces.length, 2)
    assert_includes(traces, span1)
    assert_includes(traces, span2)
  end
end
