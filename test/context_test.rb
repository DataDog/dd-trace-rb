require 'helper'
require 'ddtrace/tracer'

class ContextTest < Minitest::Test
  def test_add_span
    tracer = get_test_tracer

    ctx=Datadog::Context.new
    span = Datadog::Span.new(tracer, 'an.action')
    puts ctx
    ctx.add_span(span)
    assert_equal(1, ctx.trace.length)
    span0=ctx.trace[0]
    assert_equal('an.action', span0.name)
    assert_equal(ctx, span.context)
  end
end
