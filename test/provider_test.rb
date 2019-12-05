require 'helper'
require 'ddtrace/tracer'

class ProviderTest < Minitest::Test
  def test_default_provider
    provider = Datadog::DefaultContextProvider.new

    ctx = provider.context
    assert_kind_of(Datadog::Context, ctx)
    ctx2 = provider.context
    assert_equal(ctx, ctx2)

    span = Datadog::Span.new(nil, 'an.action')
    ctx.add_span(span)
    assert_equal(1, ctx.trace.length)
    span_check = ctx.trace[0]
    assert_equal('an.action', span_check.name)
    assert_equal(ctx, span.context)

    assert_equal(ctx, ctx2)
  end

  def test_setting_a_context
    provider = Datadog::DefaultContextProvider.new
    custom_context = Datadog::Context.new
    provider.context = custom_context

    assert_same(provider.context, custom_context)
  end
end
