require 'ddtrace/pipeline'

module Datadog
  class TestPipeline < Minitest::Test
    def setup
      @a = generate_span('a')
      @b = generate_span('b')
      @c = generate_span('c')
      @d = generate_span('d')
    end

    def teardown
      Pipeline.processors = []
    end

    def test_empty_pipeline
      assert_equal([[@a, @b, @c]], Pipeline.process!([[@a, @b, @c]]))
    end

    def test_processor_addition
      callable = ->(trace) { trace }

      assert(Pipeline.before_flush(callable))
      assert(Pipeline.before_flush(&callable))
      assert(Pipeline.before_flush(callable, callable, callable))
    end

    def test_filtering_behavior
      Pipeline.before_flush(
        Pipeline::SpanFilter.new { |span| span.name[/a|b/] }
      )

      assert_equal([[@c]], Pipeline.process!([[@a, @b, @c]]))
    end

    def test_filtering_composability
      Pipeline.before_flush(
        Pipeline::SpanFilter.new { |span| span.name[/a/] },
        Pipeline::SpanFilter.new { |span| span.name[/c/] }
      )

      assert_equal([[@b], [@d]], Pipeline.process!([[@a, @b], [@c, @d]]))
    end

    def test_filtering_and_processing
      Pipeline.before_flush(
        Pipeline::SpanFilter.new { |span| span.name[/a/] },
        Pipeline::SpanFilter.new { |span| span.name[/c/] },
        Pipeline::SpanProcessor.new { |span| span.name.upcase! },
        Pipeline::SpanProcessor.new { |span| span.name += '!' }
      )

      assert_equal([[@b], [@d]], Pipeline.process!([[@a, @b], [@c, @d]]))
      assert_equal('B!', @b.name)
      assert_equal('D!', @d.name)
    end

    def test_regular_processors
      Pipeline.before_flush(
        ->(trace) { trace if trace.size == 3 },
        ->(trace) { trace.reverse }
      )

      pipeline_result = Pipeline.process!([[1], [1, 2], [1, 2, 3]])
      assert_equal([[3, 2, 1]], pipeline_result)
    end

    private

    def generate_span(name, parent = nil)
      Span.new(nil, name).tap do |span|
        span.parent = parent
      end
    end
  end
end
