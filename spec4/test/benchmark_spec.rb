require('minitest')
require('minitest/autorun')
require('benchmark')
require('spec_helper')
require('ddtrace')
require('ddtrace/encoding')
include(Benchmark)
RSpec.describe 'benchmark traces' do
  N = 100000
  it('benchmark create traces') do
    tracer = get_test_tracer
    tracer.writer.start
    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("create #{N} traces:") do
        N.times { tracer.trace('benchmark.test').finish }
      end
    end
    expect(N).to(eq(tracer.writer.spans.length))
  end
end

RSpec.describe 'benchmark encoding' do
  N = 10000
  it('benchmark json encoder') do
    traces = get_test_traces(50)
    json_encoder = Datadog::Encoding::JSONEncoder.new
    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("Encoding #{traces.length} traces with JSON:") do
        N.times { json_encoder.encode_traces(traces) }
      end
    end
  end
  it('benchmark msgpack encoder') do
    traces = get_test_traces(50)
    msgpack_encoder = Datadog::Encoding::MsgpackEncoder.new
    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("Encoding #{traces.length} traces with Msgpack:") do
        N.times { msgpack_encoder.encode_traces(traces) }
      end
    end
  end
end
