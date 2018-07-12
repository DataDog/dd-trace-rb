require('helper')
require('minitest')
require('minitest/autorun')
class TraceBufferTest < Minitest::Test
  it('trace buffer thread safety') do
    thread_count = 100
    buffer = Datadog::TraceBuffer.new(500)
    threads = Array.new(thread_count) do |i|
      Thread.new do
        sleep((rand / 1000))
        buffer.push(i)
      end
    end
    threads.each(&:join)
    out = buffer.pop
    expect(!out.nil?).to(be_truthy)
    expected = (0..(thread_count - 1)).to_a
    expect(expected).to(eq(out.sort))
  end
  it('trace buffer with limit') do
    buffer = Datadog::TraceBuffer.new(3)
    buffer.push(1)
    buffer.push(2)
    buffer.push(3)
    buffer.push(4)
    out = buffer.pop
    expect(3).to(eq(out.length))
    expect(out.include?(4)).to(eq(true))
  end
  it('trace buffer without limit') do
    buffer = Datadog::TraceBuffer.new(0)
    buffer.push(1)
    buffer.push(2)
    buffer.push(3)
    buffer.push(4)
    out = buffer.pop
    expect(4).to(eq(out.length))
  end
  it('trace buffer empty') do
    buffer = Datadog::TraceBuffer.new(1)
    expect(buffer.empty?).to(eq(true))
    buffer.push(1)
    expect(!buffer.empty?).to(be_truthy)
  end
  it('trace buffer pop') do
    buffer = Datadog::TraceBuffer.new(0)
    input_traces = get_test_traces(2)
    buffer.push(input_traces[0])
    buffer.push(input_traces[1])
    output_traces = buffer.pop
    expect(buffer.empty?).to(eq(true))
    expect(2).to(eq(output_traces.length))
    assert_includes(output_traces, input_traces[0])
    assert_includes(output_traces, input_traces[1])
  end
  it('closed trace buffer') do
    buffer = Datadog::TraceBuffer.new(4)
    buffer.push(1)
    buffer.push(2)
    buffer.push(3)
    buffer.push(4)
    buffer.close
    buffer.push(5)
    buffer.push(6)
    out = buffer.pop
    expect(4).to(eq(out.length))
    expect(!out.include?(5)).to(be_truthy)
    expect(!out.include?(6)).to(be_truthy)
  end
end
