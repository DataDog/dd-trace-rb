require 'ddtrace/pipeline'

module Datadog
  module Pipeline
    class SpanFilterTest < Minitest::Test
      def setup
        @a = generate_span('a')
        @b = generate_span('b')
        @c = generate_span('c')
      end

      def test_pass_all_filter
        filter = SpanFilter.new { |_| false }

        assert_equal([@a, @b, @c], filter.call([@a, @b, @c]))
      end

      def test_filtering_behavior
        filter = SpanFilter.new { |span| span.name[/a|b/] }

        assert_equal([@c], filter.call([@a, @b, @c]))
      end

      def test_filtering_fail_proof
        filter = SpanFilter.new do |span|
          span.name[/b/] || raise('Boom')
        end

        assert_equal([@a, @c], filter.call([@a, @b, @c]))
      end

      def test_filtering_subtree1
        @a = generate_span('a', nil)
        @b = generate_span('b', @a)
        @c = generate_span('c', @b)
        @d = generate_span('d', nil)

        filter = SpanFilter.new { |span| span.name[/a/] }

        assert_equal([@d], filter.call([@a, @b, @c, @d]))
      end

      def test_filtering_subtree2
        @a = generate_span('a', nil)
        @b = generate_span('b', @a)
        @c = generate_span('c', @b)
        @d = generate_span('d', nil)

        filter = SpanFilter.new { |span| span.name[/b/] }

        assert_equal([@a, @d], filter.call([@a, @b, @c, @d]))
      end

      private

      def generate_span(name, parent = nil)
        Span.new(nil, name).tap do |span|
          span.parent = parent
        end
      end
    end
  end
end
