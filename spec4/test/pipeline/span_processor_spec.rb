require('ddtrace/pipeline')
module Datadog
  module Pipeline
    class SpanProcessorTest < Minitest::Test
      before do
        @a = generate_span('a')
        @b = generate_span('b')
        @c = generate_span('c')
      end
      it('empty processor') do
        processor = SpanProcessor.new { |_| }
        expect(processor.call([@a, @b, @c])).to(eq([@a, @b, @c]))
      end
      it('return value independence') do
        processor = SpanProcessor.new { |_| false }
        expect(processor.call([@a, @b, @c])).to(eq([@a, @b, @c]))
      end
      it('processing') do
        processor = SpanProcessor.new { |span| span.name += '!' }
        processing_result = processor.call([@a, @b, @c])
        expect(processing_result).to(eq([@a, @b, @c]))
        expect(processing_result.map(&:name)).to(eq(['a!', 'b!', 'c!']))
      end
      it('processing fail proof') do
        processor = SpanProcessor.new do |span|
          span.name += '!'
          raise('Boom!')
        end
        processing_result = processor.call([@a, @b, @c])
        expect(processing_result).to(eq([@a, @b, @c]))
        expect(processing_result.map(&:name)).to(eq(['a!', 'b!', 'c!']))
      end

      private

      def generate_span(name, parent = nil)
        Span.new(nil, name).tap { |span| span.parent = parent }
      end
    end
  end
end
