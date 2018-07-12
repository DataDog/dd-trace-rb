require('ddtrace/pipeline')
RSpec.describe Datadog::Pipeline do
  before do
    @a = generate_span('a')
    @b = generate_span('b')
    @c = generate_span('c')
    @d = generate_span('d')
  end
  after { Datadog::Pipeline.processors = [] }
  it('empty pipeline') do
    expect(Datadog::Pipeline.process!([[@a, @b, @c]])).to(eq([[@a, @b, @c]]))
  end
  it('processor addition') do
    callable = ->(trace) { trace }
    expect(Datadog::Pipeline.before_flush(callable)).to(be_truthy)
    expect(Datadog::Pipeline.before_flush(&callable)).to(be_truthy)
    expect(Datadog::Pipeline.before_flush(callable, callable, callable)).to(be_truthy)
  end
  it('filtering behavior') do
    Datadog::Pipeline.before_flush(Datadog::Pipeline::SpanFilter.new { |span| span.name[/a|b/] })
    expect(Datadog::Pipeline.process!([[@a, @b, @c]])).to(eq([[@c]]))
  end
  it('filtering composability') do
    Datadog::Pipeline.before_flush(Datadog::Pipeline::SpanFilter.new { |span| span.name[/a/] },
                                   Datadog::Pipeline::SpanFilter.new { |span| span.name[/c/] })
    expect(Datadog::Pipeline.process!([[@a, @b], [@c, @d]])).to(eq([[@b], [@d]]))
  end
  it('filtering and processing') do
    Datadog::Pipeline.before_flush(Datadog::Pipeline::SpanFilter.new { |span| span.name[/a/] },
                                   Datadog::Pipeline::SpanFilter.new { |span| span.name[/c/] },
                                   Datadog::Pipeline::SpanProcessor.new { |span| span.name.upcase! },
                                   Datadog::Pipeline::SpanProcessor.new { |span| span.name += '!' })
    expect(Datadog::Pipeline.process!([[@a, @b], [@c, @d]])).to(eq([[@b], [@d]]))
    expect(@b.name).to(eq('B!'))
    expect(@d.name).to(eq('D!'))
  end
  it('regular processors') do
    Datadog::Pipeline.before_flush(->(trace) { trace if trace.size == 3 }, ->(trace) { trace.reverse })
    pipeline_result = Datadog::Pipeline.process!([[1], [1, 2], [1, 2, 3]])
    expect(pipeline_result).to(eq([[3, 2, 1]]))
  end

  private

  def generate_span(name, parent = nil)
    Datadog::Span.new(nil, name).tap { |span| span.parent = parent }
  end
end
