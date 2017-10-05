require 'ddtrace/filter_pipeline'

module Datadog
  class FilterPipelineTest < Minitest::Test
    def setup
      @pipeline = FilterPipeline.new

      @a = generate_span('a')
      @b = generate_span('b')
      @c = generate_span('c')
    end

    def test_empty_pipeline
      assert_equal([@a, @b, @c], @pipeline.call([@a, @b, @c]))
    end

    def test_filter_addition
      assert(@pipeline.add_filter(->(_) { true }))

      assert(@pipeline.add_filter { |_| false })

      assert_raises(ArgumentError) do
        @pipeline.add_filter('foobar')
      end
    end

    def test_filtering_behavior
      @pipeline.add_filter { |span| span.name[/a|b/] }

      assert_equal([@c], @pipeline.call([@a, @b, @c]))
    end

    def test_filtering_composability
      @pipeline.add_filter { |span| span.name[/a/] }
      @pipeline.add_filter { |span| span.name[/c/] }

      assert_equal([@b], @pipeline.call([@a, @b, @c]))
    end

    def test_filtering_fail_proof
      @pipeline.add_filter { |span| span.name[/c/] }
      @pipeline.add_filter { |_| raise('Boom') }

      assert_equal([@a, @b], @pipeline.call([@a, @b, @c]))
    end

    def test_filtering_subtree1
      @a = generate_span('a', nil)
      @b = generate_span('b', @a)
      @c = generate_span('c', @b)
      @d = generate_span('d', nil)

      @pipeline.add_filter { |span| span.name[/a/] }

      assert_equal([@d], @pipeline.call([@a, @b, @c, @d]))
    end

    def test_filtering_subtree2
      @a = generate_span('a', nil)
      @b = generate_span('b', @a)
      @c = generate_span('c', @b)
      @d = generate_span('d', nil)

      @pipeline.add_filter { |span| span.name[/b/] }

      assert_equal([@a, @d], @pipeline.call([@a, @b, @c, @d]))
    end

    private

    def generate_span(name, parent = nil)
      Span.new(nil, name).tap do |span|
        span.parent = parent
      end
    end
  end
end
