require 'minitest'
require 'minitest/autorun'
require 'benchmark'

require 'helper'
require 'ddtrace'

include Benchmark

class TraceBufferTest < Minitest::Test
  N = 100000

  def test_benchmark_create_traces
    # create and finish a huge number of spans with a single thread
    tracer = get_test_tracer()

    Benchmark.benchmark(CAPTION, 7, FORMAT, '>total:', '>avg:') do |x|
      x.report("create #{N} traces:") do
        N.times { tracer.trace('benchmark.test').finish() }
      end
    end

    assert_equal(tracer.writer.spans.length, N)
  end
end
