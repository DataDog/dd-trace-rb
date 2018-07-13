require('spec_helper')
require('ddtrace/tracer')
RSpec.describe Datadog::DefaultContextProvider do
  it('default provider') do
    provider = described_class.new
    ctx = provider.context
    assert_kind_of(Datadog::Context, ctx)
    ctx2 = provider.context
    expect(ctx2).to(eq(ctx))
    span = Datadog::Span.new(nil, 'an.action')
    ctx.add_span(span)
    expect(ctx.trace.length).to(eq(1))
    span_check = ctx.trace[0]
    expect(span_check.name).to(eq('an.action'))
    expect(span.context).to(eq(ctx))
    expect(ctx2).to(eq(ctx))
  end
  it('setting a context') do
    provider = described_class.new
    custom_context = Datadog::Context.new
    provider.context = custom_context
    assert_same(provider.context, custom_context)
  end
end
