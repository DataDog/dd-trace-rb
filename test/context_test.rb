require 'helper'
require 'ddtrace/tracer'

class ContextTest < Minitest::Test
  def test_nil_tracer
    ctx = Datadog::Context.new

    span = Datadog::Span.new(nil, 'an.action')
    ctx.add_span(span)
    assert_equal(1, ctx.trace.length)
    span_check = ctx.trace[0]
    assert_equal('an.action', span_check.name)
    assert_equal(ctx, span.context)
  end

  def test_add_span
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    span = Datadog::Span.new(tracer, 'an.action')
    ctx.add_span(span)
    assert_equal(1, ctx.trace.length)
    span_check = ctx.trace[0]
    assert_equal('an.action', span_check.name)
    assert_equal(ctx, span.context)
  end

  def test_add_span_n
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    n = 10
    n.times do |i|
      span = Datadog::Span.new(tracer, "an.action#{i}")
      ctx.add_span(span)
    end
    assert_equal(n, ctx.trace.length)
    n.times do |i|
      span_check = ctx.trace[i]
      assert_equal("an.action#{i}", span_check.name)
    end
  end

  def test_context_sampled
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_equal(false, ctx.sampled?)
    span = Datadog::Span.new(tracer, 'an.action')
    ctx.add_span(span)
    assert_equal(true, ctx.sampled?)
  end

  def test_context_sampled_false
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_equal(false, ctx.sampled?)
    span = Datadog::Span.new(tracer, 'an.action')
    span.sampled = false
    ctx.add_span(span)
    assert_equal(false, ctx.sampled?)
  end

  def test_current_span
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    n = 10
    n.times do |i|
      span = Datadog::Span.new(tracer, "an.action#{i}")
      ctx.add_span(span)
      assert_equal(span, ctx.current_span)
    end
  end
end
