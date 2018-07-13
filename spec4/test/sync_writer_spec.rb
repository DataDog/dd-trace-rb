require('minitest')
require('ddtrace')
require('spec_helper')
require('ddtrace/sync_writer')
class SpyTransport
  def initialize
    @mutex = Mutex.new
  end

  def send(*call_arguments)
    @mutex.synchronize { (calls << call_arguments) }
  end

  def calls
    @calls ||= []
  end
end

RSpec.describe Datadog::SyncWriter do
  before do
    @transport = SpyTransport.new
    @sync_writer = described_class.new(transport: @transport)
  end

  it('sync write') do
    trace = get_test_traces(1).first
    services = get_test_services
    @sync_writer.write(trace, services)
    expect(@transport.calls).to include([:traces, [trace]])
    expect(@transport.calls).to include([:services, services])
  end

  it('sync write filtering') do
    trace1 = [Span.new(nil, 'span_1')]
    trace2 = [Span.new(nil, 'span_2')]
    Pipeline.before_flush(Pipeline::SpanFilter.new { |span| (span.name == 'span_1') })
    @sync_writer.write(trace1, {})
    @sync_writer.write(trace2, {})
    expect(@transport.calls).not_to include([:traces, [trace1]])
    expect(@transport.calls).to include([:traces, [trace2]])
  end

  it('integration with tracer') do
    tracer = Tracer.new(writer: @sync_writer)
    span = tracer.start_span('foo.bar')
    span.finish
    expect(@transport.calls).to include([:traces, [[span]]])
  end

  after { Pipeline.processors = [] }
end
