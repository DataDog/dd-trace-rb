require 'minitest'
require 'minitest/autorun'
require 'benchmark'

require 'helper'
require 'ddtrace'
require 'ddtrace/encoding'

include Benchmark

class TraceBufferTest < Minitest::Test
  N = 100000

  def test_benchmark_create_traces
    # create and finish a huge number of spans with a single thread
    tracer = get_test_tracer
    tracer.writer.start

    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("create #{N} traces:") do
        N.times { tracer.trace('benchmark.test').finish }
      end
    end

    assert_equal(tracer.writer.spans.length, N)
  end
end

class EncoderTest < Minitest::Test
  N = 10000

  def test_benchmark_json_encoder
    # create and finish a huge number of spans with a single thread
    traces = get_test_traces(50)
    json_encoder = Datadog::Encoding::JSONEncoder

    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("Encoding #{traces.length} traces with JSON:") do
        N.times { json_encoder.encode(traces.map { |t| t.map(&:to_hash) }) {} }
      end
    end
  end

  def test_benchmark_msgpack_encoder
    # create and finish a huge number of spans with a single thread
    traces = get_test_traces(50)
    msgpack_encoder = Datadog::Encoding::MsgpackEncoder

    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("Encoding #{traces.length} traces with Msgpack:") do
        N.times { msgpack_encoder.encode(traces.map { |t| t.map(&:to_hash) }) {} }
      end
    end
  end
end
