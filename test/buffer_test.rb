# require 'helper'

# require 'minitest'
# require 'minitest/autorun'

# class TraceBufferTest < Minitest::Test
#   def test_trace_buffer_thread_safety
#     # ensures that the buffer is thread safe
#     thread_count = 100
#     buffer = Datadog::TraceBuffer.new(500)

#     threads = Array.new(thread_count) do |i|
#       Thread.new do
#         sleep(rand / 1000)
#         buffer.push(i)
#       end
#     end

#     threads.each(&:join)
#     out = buffer.pop
#     assert !out.nil?
#     expected = (0..thread_count - 1).to_a
#     assert_equal(out.sort, expected)
#   end

#   def test_trace_buffer_with_limit
#     # ensures that the buffer has max size
#     buffer = Datadog::TraceBuffer.new(3)
#     buffer.push(1)
#     buffer.push(2)
#     buffer.push(3)
#     buffer.push(4)
#     out = buffer.pop
#     assert_equal(out.length, 3)
#     assert out.include?(4)
#   end

#   def test_trace_buffer_without_limit
#     # the trace buffer has an unlimited size if created with
#     # a zero (or negative) value
#     buffer = Datadog::TraceBuffer.new(0)
#     buffer.push(1)
#     buffer.push(2)
#     buffer.push(3)
#     buffer.push(4)
#     out = buffer.pop
#     assert_equal(out.length, 4)
#   end

#   def test_trace_buffer_empty
#     # ensures empty? works as expected
#     buffer = Datadog::TraceBuffer.new(1)
#     assert buffer.empty?
#     buffer.push(1)
#     assert !buffer.empty?
#   end

#   def test_trace_buffer_pop
#     # the trace buffer must return all internal traces
#     buffer = Datadog::TraceBuffer.new(0)
#     input_traces = get_test_traces(2)
#     buffer.push(input_traces[0])
#     buffer.push(input_traces[1])
#     # collect traces
#     output_traces = buffer.pop()
#     # the buffer must be empty
#     assert buffer.empty?
#     assert_equal(output_traces.length, 2)
#     assert_includes(output_traces, input_traces[0])
#     assert_includes(output_traces, input_traces[1])
#   end
# end
