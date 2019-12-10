require 'helper'
require 'ddtrace/tracer'

# rubocop:disable Metrics/ClassLength
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

  def test_initialize
    ctx = Datadog::Context.new
    assert_nil(ctx.trace_id)
    assert_nil(ctx.span_id)
    assert_nil(ctx.sampling_priority)
    assert_nil(ctx.origin)
    assert_equal(false, ctx.sampled)
    assert_equal(false, ctx.finished?)

    ctx = Datadog::Context.new(trace_id: 123, span_id: 456, sampling_priority: 1, sampled: true)
    assert_equal(123, ctx.trace_id)
    assert_equal(456, ctx.span_id)
    assert_equal(1, ctx.sampling_priority)
    assert_equal(true, ctx.sampled)
    assert_equal(false, ctx.finished?)

    ctx = Datadog::Context.new(trace_id: 123, span_id: 456, sampling_priority: 1, origin: 'synthetics', sampled: true)
    assert_equal(123, ctx.trace_id)
    assert_equal(456, ctx.span_id)
    assert_equal(1, ctx.sampling_priority)
    assert_equal('synthetics', ctx.origin)
    assert_equal(true, ctx.sampled)
    assert_equal(false, ctx.finished?)
  end

  def test_trace_id
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_nil(ctx.trace_id)

    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)

    assert_equal(span.trace_id, ctx.trace_id)
  end

  def test_span_id
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_nil(ctx.span_id)

    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)

    assert_equal(span.span_id, ctx.span_id)
  end

  def test_sampling_priority
    ctx = Datadog::Context.new

    assert_nil(ctx.sampling_priority)

    [Datadog::Ext::Priority::USER_REJECT,
     Datadog::Ext::Priority::AUTO_REJECT,
     Datadog::Ext::Priority::AUTO_KEEP,
     Datadog::Ext::Priority::USER_KEEP,
     nil, 999].each do |sampling_priority|
      ctx.sampling_priority = sampling_priority
      if sampling_priority
        assert_equal(sampling_priority, ctx.sampling_priority)
      else
        assert_nil(ctx.sampling_priority)
      end
    end
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

  # rubocop:disable Metrics/MethodLength
  def test_log_unfinished_spans
    tracer = get_test_tracer

    default_log = Datadog::Logger.log
    default_level = Datadog::Logger.log.level

    buf = StringIO.new

    Datadog::Logger.log = Datadog::Logger.new(buf)
    Datadog::Logger.log.level = ::Logger::DEBUG

    assert_equal(true, Datadog::Logger.log.debug?)
    assert_equal(true, Datadog::Logger.log.info?)
    assert_equal(true, Datadog::Logger.log.warn?)
    assert_equal(true, Datadog::Logger.log.error?)
    assert_equal(true, Datadog::Logger.log.fatal?)

    root = Datadog::Span.new(tracer, 'parent')
    child1 = Datadog::Span.new(tracer, 'child_1', trace_id: root.trace_id, parent_id: root.span_id)
    child2 = Datadog::Span.new(tracer, 'child_2', trace_id: root.trace_id, parent_id: root.span_id)
    child1.parent = root
    child2.parent = root
    ctx = Datadog::Context.new
    ctx.add_span(root)
    ctx.add_span(child1)
    ctx.add_span(child2)

    root.finish()
    lines = buf.string.lines

    assert_operator(3, :<=, lines.length, 'there should be at least 3 log messages') if lines.respond_to? :length

    # Test below iterates on lines, this is required for Ruby 1.9 backward compatibility.
    i = 0
    lines.each do |l|
      case i
      when 0
        assert_match(
          /D,.*DEBUG -- ddtrace: \[ddtrace\].*\) root span parent closed but has 2 unfinished spans:/,
          l
        )
      when 1
        assert_match(
          /D,.*DEBUG -- ddtrace: \[ddtrace\].*\) unfinished span: Span\(name:child_1/,
          l
        )
      when 2
        assert_match(
          /D,.*DEBUG -- ddtrace: \[ddtrace\].*\) unfinished span: Span\(name:child_2/,
          l
        )
      end
      i += 1
    end

    Datadog::Logger.log = default_log
    Datadog::Logger.log.level = default_level
  end

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

  def test_length
    tracer = get_test_tracer
    ctx = Datadog::Context.new

    assert_equal(0, ctx.send(:length))
    10.times do |i|
      span = Datadog::Span.new(tracer, "test.op#{i}")
      assert_equal(i, ctx.send(:length))
      ctx.add_span(span)
      assert_equal(i + 1, ctx.send(:length))
      ctx.close_span(span)
      assert_equal(i + 1, ctx.send(:length))
    end

    ctx.get

    assert_equal(0, ctx.send(:length))
  end

  def test_start_time
    tracer = get_test_tracer
    ctx = tracer.call_context

    assert_nil(ctx.send(:start_time))
    tracer.trace('test.op') do |span|
      assert_equal(span.start_time, ctx.send(:start_time))
    end
    assert_nil(ctx.send(:start_time))
  end

  def test_each_span
    span = Datadog::Span.new(nil, 'test.op')
    ctx = Datadog::Context.new
    ctx.add_span(span)

    action = MiniTest::Mock.new
    action.expect(:call_with_name, nil, ['test.op'])
    ctx.send(:each_span) do |s|
      action.call_with_name(s.name)
    end
    action.verify
  end

  def test_delete_span_if
    tracer = get_test_tracer
    ctx = tracer.call_context

    action = MiniTest::Mock.new
    action.expect(:call_with_name, nil, ['test.op2'])
    tracer.trace('test.op1') do
      tracer.trace('test.op2') do
        assert_equal(2, ctx.send(:length))
        ctx.send(:delete_span_if) { |span| span.name == 'test.op1' }
        assert_equal(1, ctx.send(:length))
        ctx.send(:each_span) do |s|
          action.call_with_name(s.name)
        end
        assert_equal(false, ctx.finished?, 'context is not finished as op2 is not finished')
        tracer.trace('test.op3') do
        end
        assert_equal(2, ctx.send(:length))
        ctx.send(:delete_span_if) { |span| span.name == 'test.op3' }
        assert_equal(1, ctx.send(:length))
      end
      assert_equal(0, ctx.send(:length), 'op2 has been finished, so context has been finished too')
    end
    action.verify
  end

  def test_max_length
    tracer = get_test_tracer

    ctx = Datadog::Context.new
    assert_equal(Datadog::Context::DEFAULT_MAX_LENGTH, ctx.max_length)

    max_length = 3
    ctx = Datadog::Context.new(max_length: max_length)
    assert_equal(max_length, ctx.max_length)

    spans = []
    (max_length * 2).times do |i|
      span = tracer.start_span("test.op#{i}", child_of: ctx)
      spans << span
    end

    assert_equal(max_length, ctx.send(:length))
    trace, = ctx.get
    assert_nil(trace)

    spans.each(&:finish)

    assert_equal(0, ctx.send(:length), "context #{ctx}")
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
