require 'helper'
require 'ddtrace/tracer'

class ContextTest < Minitest::Test
  def test_nil_tracer
    ctx = Datadog::Context.new

    span = Datadog::Span.new(nil, 'test.op')
    ctx.add_span(span)
    assert_equal(1, ctx.trace.length)
    span_check = ctx.trace[0]
    assert_equal('test.op', span_check.name)
    assert_equal(ctx, span.context)
  end

  def test_add_span
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    assert_equal(1, ctx.trace.length)
    span_check = ctx.trace[0]
    assert_equal('test.op', span_check.name)
    assert_equal(ctx, span.context)
  end

  def test_add_span_n
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    n = 10
    n.times do |i|
      span = Datadog::Span.new(tracer, "test.op#{i}")
      ctx.add_span(span)
    end
    assert_equal(n, ctx.trace.length)
    n.times do |i|
      span_check = ctx.trace[i]
      assert_equal("test.op#{i}", span_check.name)
    end
  end

  def test_context_sampled
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_equal(false, ctx.sampled?)
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    assert_equal(true, ctx.sampled?)
  end

  def test_context_sampled_false
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_equal(false, ctx.sampled?)
    span = Datadog::Span.new(tracer, 'test.op')
    span.sampled = false
    ctx.add_span(span)
    assert_equal(false, ctx.sampled?)
  end

  def test_current_span
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    n = 10
    n.times do |i|
      span = Datadog::Span.new(tracer, "test.op#{i}")
      ctx.add_span(span)
      assert_equal(span, ctx.current_span)
    end
  end

  def test_close_span
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    ctx.close_span(span)
    assert_equal(1, ctx.finished_spans)
    assert_nil(ctx.current_span)
  end

  def test_get
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    ctx.close_span(span)
    trace, sampled = ctx.get
    refute_nil(trace)
    assert_equal(1, trace.length)
    assert_equal(true, sampled)
    assert_equal(0, ctx.trace.length)
    assert_equal(0, ctx.finished_spans)
    assert_nil(ctx.current_span)
    assert_equal(false, ctx.sampled)
  end

  def test_finished
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_equal(false, ctx.finished?)
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    assert_equal(false, ctx.finished?)
    ctx.close_span(span)
    assert_equal(true, ctx.finished?)
  end

  # [TODO:christian] implement test_log_unfinished_spans

  def test_thread_safe
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    n = 100
    threads = []
    spans = []
    mutex = Mutex.new

    n.times do |i|
      threads << Thread.new do
        span = Datadog::Span.new(tracer, "test.op#{i}")
        ctx.add_span(span)
        mutex.synchronize do
          spans << span
        end
      end
    end
    threads.each(&:join)

    assert_equal(n, ctx.trace.length)

    threads = []
    spans.each do |span|
      threads << Thread.new do
        ctx.close_span(span)
      end
    end
    threads.each(&:join)

    trace, sampled = ctx.get

    assert_equal(n, trace.length)
    assert_equal(true, sampled)
    assert_equal(0, ctx.trace.length)
    assert_equal(0, ctx.finished_spans)
    assert_nil(ctx.current_span)
    assert_equal(false, ctx.sampled)
  end
end

class ThreadLocalContextTest < Minitest::Test
  def test_get
    local_ctx = Datadog::ThreadLocalContext.new
    ctx = local_ctx.local
    refute_nil(ctx)
    assert_instance_of(Datadog::Context, ctx)
  end

  def test_set
    tracer = get_test_tracer
    local_ctx = Datadog::ThreadLocalContext.new
    ctx = Datadog::Context.new

    span = Datadog::Span.new(tracer, 'test.op')
    span.finish

    local_ctx.local = ctx
    ctx2 = local_ctx.local

    assert_equal(ctx, ctx2)
  end

  def test_multiple_threads_multiple_context
    tracer = get_test_tracer
    local_ctx = Datadog::ThreadLocalContext.new

    n = 100
    threads = []
    spans = []
    mutex = Mutex.new

    n.times do |i|
      threads << Thread.new do
        span = Datadog::Span.new(tracer, "test.op#{i}")
        ctx = local_ctx.local
        ctx.add_span(span)
        assert_equal(1, ctx.trace.length)
        mutex.synchronize do
          spans << span
        end
      end
    end
    threads.each(&:join)

    # the main instance should have an empty Context
    # because it has not been used in this thread
    ctx = local_ctx.local
    assert_equal(0, ctx.trace.length)

    threads = []
    spans.each do |span|
      threads << Thread.new do
        ctx.close_span(span)
      end
    end
    threads.each(&:join)
  end
end
