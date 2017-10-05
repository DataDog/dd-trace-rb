require 'ddtrace/pipeline'

module Datadog
  module Pipeline
    class SpanProcessorTest < Minitest::Test
      def setup
        @a = generate_span('a')
        @b = generate_span('b')
        @c = generate_span('c')
      end

      def test_empty_processor
        processor = SpanProcessor.new { |_| }

        assert_equal([@a, @b, @c], processor.call([@a, @b, @c]))
      end

      def test_return_value_independence
        processor = SpanProcessor.new { |_| false }

        assert_equal([@a, @b, @c], processor.call([@a, @b, @c]))
      end

      def test_processing
        processor = SpanProcessor.new do |span|
          span.name += '!'
        end

        processing_result = processor.call([@a, @b, @c])

        assert_equal([@a, @b, @c], processing_result)
        assert_equal(['a!', 'b!', 'c!'], processing_result.map(&:name))
      end

      def test_processing_fail_proof
        processor = SpanProcessor.new do |span|
          span.name += '!'
          raise('Boom!')
        end

        processing_result = processor.call([@a, @b, @c])

        assert_equal([@a, @b, @c], processing_result)
        assert_equal(['a!', 'b!', 'c!'], processing_result.map(&:name))
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
