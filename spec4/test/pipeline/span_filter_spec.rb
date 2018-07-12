require('ddtrace/pipeline')
module Datadog
  module Pipeline
    class SpanFilterTest < Minitest::Test
      before do
        @a = generate_span('a')
        @b = generate_span('b')
        @c = generate_span('c')
      end
      it('pass all filter') do
        filter = SpanFilter.new { |_| false }
        expect(filter.call([@a, @b, @c])).to(eq([@a, @b, @c]))
      end
      it('filtering behavior') do
        filter = SpanFilter.new { |span| span.name[/a|b/] }
        expect(filter.call([@a, @b, @c])).to(eq([@c]))
      end
      it('filtering fail proof') do
        filter = SpanFilter.new { |span| (span.name[/b/] || raise('Boom')) }
        expect(filter.call([@a, @b, @c])).to(eq([@a, @c]))
      end
      it('filtering subtree1') do
        @a = generate_span('a', nil)
        @b = generate_span('b', @a)
        @c = generate_span('c', @b)
        @d = generate_span('d', nil)
        filter = SpanFilter.new { |span| span.name[/a/] }
        expect(filter.call([@a, @b, @c, @d])).to(eq([@d]))
      end
      it('filtering subtree2') do
        @a = generate_span('a', nil)
        @b = generate_span('b', @a)
        @c = generate_span('c', @b)
        @d = generate_span('d', nil)
        filter = SpanFilter.new { |span| span.name[/b/] }
        expect(filter.call([@a, @b, @c, @d])).to(eq([@a, @d]))
      end

      private

      def generate_span(name, parent = nil)
        Span.new(nil, name).tap { |span| span.parent = parent }
      end
    end
  end
end
