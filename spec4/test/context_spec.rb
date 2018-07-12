require('helper')
require('ddtrace/tracer')
RSpec.describe Datadog::Context do
  it('nil tracer') do
    ctx = described_class.new
    span = Datadog::Span.new(nil, 'test.op')
    ctx.add_span(span)
    expect(ctx.trace.length).to(eq(1))
    span_check = ctx.trace[0]
    expect(span_check.name).to(eq('test.op'))
    expect(span.context).to(eq(ctx))
  end
  it('initialize') do
    ctx = described_class.new
    expect(ctx.trace_id).to(be_nil)
    expect(ctx.span_id).to(be_nil)
    expect(ctx.sampling_priority).to(be_nil)
    expect(ctx.sampled).to(eq(false))
    expect(ctx.finished?).to(eq(false))
    ctx = described_class.new(trace_id: 123, span_id: 456, sampling_priority: 1, sampled: true)
    expect(ctx.trace_id).to(eq(123))
    expect(ctx.span_id).to(eq(456))
    expect(ctx.sampling_priority).to(eq(1))
    expect(ctx.sampled).to(eq(true))
    expect(ctx.finished?).to(eq(false))
  end
  it('trace id') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.trace_id).to(be_nil)
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    expect(ctx.trace_id).to(eq(span.trace_id))
  end
  it('span id') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.span_id).to(be_nil)
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    expect(ctx.span_id).to(eq(span.span_id))
  end
  it('sampling priority') do
    ctx = described_class.new
    expect(ctx.sampling_priority).to(be_nil)
    [
      Datadog::Ext::Priority::USER_REJECT,
      Datadog::Ext::Priority::AUTO_REJECT,
      Datadog::Ext::Priority::AUTO_KEEP,
      Datadog::Ext::Priority::USER_KEEP,
      nil,
      999
    ].each do |sampling_priority|
      ctx.sampling_priority = sampling_priority
      if sampling_priority
        expect(ctx.sampling_priority).to(eq(sampling_priority))
      else
        expect(ctx.sampling_priority).to(be_nil)
      end
    end
  end
  it('add span') do
    tracer = get_test_tracer
    ctx = described_class.new
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    expect(ctx.trace.length).to(eq(1))
    span_check = ctx.trace[0]
    expect(span_check.name).to(eq('test.op'))
    expect(span.context).to(eq(ctx))
  end
  it('add span n') do
    tracer = get_test_tracer
    ctx = described_class.new
    n = 10
    n.times do |i|
      span = Datadog::Span.new(tracer, "test.op#{i}")
      ctx.add_span(span)
    end
    expect(ctx.trace.length).to(eq(n))
    n.times do |i|
      span_check = ctx.trace[i]
      expect(span_check.name).to(eq("test.op#{i}"))
    end
  end
  it('context sampled') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.sampled?).to(eq(false))
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    expect(ctx.sampled?).to(eq(true))
  end
  it('context sampled false') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.sampled?).to(eq(false))
    span = Datadog::Span.new(tracer, 'test.op')
    span.sampled = false
    ctx.add_span(span)
    expect(ctx.sampled?).to(eq(false))
  end
  it('current span') do
    tracer = get_test_tracer
    ctx = described_class.new
    n = 10
    n.times do |i|
      span = Datadog::Span.new(tracer, "test.op#{i}")
      ctx.add_span(span)
      expect(ctx.current_span).to(eq(span))
    end
  end
  it('close span') do
    tracer = get_test_tracer
    ctx = described_class.new
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    ctx.close_span(span)
    expect(ctx.finished_spans).to(eq(1))
    expect(ctx.current_span).to(be_nil)
  end
  it('get') do
    tracer = get_test_tracer
    ctx = described_class.new
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    ctx.close_span(span)
    trace, sampled = ctx.get
    refute_nil(trace)
    expect(trace.length).to(eq(1))
    expect(sampled).to(eq(true))
    expect(ctx.trace.length).to(eq(0))
    expect(ctx.finished_spans).to(eq(0))
    expect(ctx.current_span).to(be_nil)
    expect(ctx.sampled).to(eq(false))
  end
  it('finished') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.finished?).to(eq(false))
    span = Datadog::Span.new(tracer, 'test.op')
    ctx.add_span(span)
    expect(ctx.finished?).to(eq(false))
    ctx.close_span(span)
    expect(ctx.finished?).to(eq(true))
  end
  it('log unfinished spans') do
    tracer = get_test_tracer
    default_log = Datadog::Tracer.log
    default_level = Datadog::Tracer.log.level
    buf = StringIO.new
    Datadog::Tracer.log = Datadog::Logger.new(buf)
    Datadog::Tracer.log.level = ::Logger::DEBUG
    expect(Datadog::Tracer.log.debug?).to(eq(true))
    expect(Datadog::Tracer.log.info?).to(eq(true))
    expect(Datadog::Tracer.log.warn?).to(eq(true))
    expect(Datadog::Tracer.log.error?).to(eq(true))
    expect(Datadog::Tracer.log.fatal?).to(eq(true))
    root = Datadog::Span.new(tracer, 'parent')
    child1 = Datadog::Span.new(tracer, 'child_1', trace_id: root.trace_id, parent_id: root.span_id)
    child2 = Datadog::Span.new(tracer, 'child_2', trace_id: root.trace_id, parent_id: root.span_id)
    child1.parent = root
    child2.parent = root
    ctx = described_class.new
    ctx.add_span(root)
    ctx.add_span(child1)
    ctx.add_span(child2)
    root.finish
    lines = buf.string.lines
    if lines.respond_to?(:length)
      assert_operator(3, :<=, lines.length, 'there should be at least 3 log messages')
    end
    i = 0
    lines.each do |l|
      case i
      when 0 then
        expect(l).to(match(/D,.*DEBUG -- ddtrace: \[ddtrace\].*\) root span parent closed but has 2 unfinished spans:/))
      when 1 then
        expect(l).to(match(/D,.*DEBUG -- ddtrace: \[ddtrace\].*\) unfinished span: Span\(name:child_1/))
      when 2 then
        expect(l).to(match(/D,.*DEBUG -- ddtrace: \[ddtrace\].*\) unfinished span: Span\(name:child_2/))
      end
      i = (i + 1)
    end
    Datadog::Tracer.log = default_log
    Datadog::Tracer.log.level = default_level
  end
  it('thread safe') do
    tracer = get_test_tracer
    ctx = described_class.new
    n = 100
    threads = []
    spans = []
    mutex = Mutex.new
    n.times do |i|
      (threads << Thread.new do
        span = Datadog::Span.new(tracer, "test.op#{i}")
        ctx.add_span(span)
        mutex.synchronize { (spans << span) }
      end)
    end
    threads.each(&:join)
    expect(ctx.trace.length).to(eq(n))
    threads = []
    spans.each { |span| (threads << Thread.new { ctx.close_span(span) }) }
    threads.each(&:join)
    trace, sampled = ctx.get
    expect(trace.length).to(eq(n))
    expect(sampled).to(eq(true))
    expect(ctx.trace.length).to(eq(0))
    expect(ctx.finished_spans).to(eq(0))
    expect(ctx.current_span).to(be_nil)
    expect(ctx.sampled).to(eq(false))
  end
  it('length') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.send(:length)).to(eq(0))
    10.times do |i|
      span = Datadog::Span.new(tracer, "test.op#{i}")
      expect(ctx.send(:length)).to(eq(i))
      ctx.add_span(span)
      expect(ctx.send(:length)).to(eq((i + 1)))
      ctx.close_span(span)
      expect(ctx.send(:length)).to(eq((i + 1)))
    end
    ctx.get
    expect(ctx.send(:length)).to(eq(0))
  end
  it('start time') do
    tracer = get_test_tracer
    ctx = tracer.call_context
    expect(ctx.send(:start_time)).to(be_nil)
    tracer.trace('test.op') do |span|
      expect(ctx.send(:start_time)).to(eq(span.start_time))
    end
    expect(ctx.send(:start_time)).to(be_nil)
  end
  it('each span') do
    span = Datadog::Span.new(nil, 'test.op')
    ctx = described_class.new
    ctx.add_span(span)
    action = MiniTest::Mock.new
    action.expect(:call_with_name, nil, ['test.op'])
    ctx.send(:each_span) { |s| action.call_with_name(s.name) }
    action.verify
  end
  it('delete span if') do
    tracer = get_test_tracer
    ctx = tracer.call_context
    action = MiniTest::Mock.new
    action.expect(:call_with_name, nil, ['test.op2'])
    tracer.trace('test.op1') do
      tracer.trace('test.op2') do
        expect(ctx.send(:length)).to(eq(2))
        ctx.send(:delete_span_if) { |span| (span.name == 'test.op1') }
        expect(ctx.send(:length)).to(eq(1))
        ctx.send(:each_span) { |s| action.call_with_name(s.name) }
        expect(ctx.finished?).to(eq(false))
        tracer.trace('test.op3') {}
        expect(ctx.send(:length)).to(eq(2))
        ctx.send(:delete_span_if) { |span| (span.name == 'test.op3') }
        expect(ctx.send(:length)).to(eq(1))
      end
      expect(ctx.send(:length)).to(eq(0))
    end
    action.verify
  end
  it('max length') do
    tracer = get_test_tracer
    ctx = described_class.new
    expect(ctx.max_length).to(eq(described_class::DEFAULT_MAX_LENGTH))
    max_length = 3
    ctx = described_class.new(max_length: max_length)
    expect(ctx.max_length).to(eq(max_length))
    spans = []
    (max_length * 2).times do |i|
      span = tracer.start_span("test.op#{i}", child_of: ctx)
      (spans << span)
    end
    expect(ctx.send(:length)).to(eq(max_length))
    trace = ctx.get
    expect(trace).to(be_nil)
    spans.each(&:finish)
    expect(ctx.send(:length)).to(eq(0))
  end
end
class ThreadLocalContextTest < Minitest::Test
  it('get') do
    local_ctx = Datadog::ThreadLocalContext.new
    ctx = local_ctx.local
    refute_nil(ctx)
    assert_instance_of(described_class, ctx)
  end
  it('set') do
    tracer = get_test_tracer
    local_ctx = Datadog::ThreadLocalContext.new
    ctx = described_class.new
    span = Datadog::Span.new(tracer, 'test.op')
    span.finish
    local_ctx.local = ctx
    ctx2 = local_ctx.local
    expect(ctx2).to(eq(ctx))
  end
  it('multiple threads multiple context') do
    tracer = get_test_tracer
    local_ctx = Datadog::ThreadLocalContext.new
    n = 100
    threads = []
    spans = []
    mutex = Mutex.new
    n.times do |i|
      (threads << Thread.new do
        span = Datadog::Span.new(tracer, "test.op#{i}")
        ctx = local_ctx.local
        ctx.add_span(span)
        assert_equal(1, ctx.trace.length)
        mutex.synchronize { (spans << span) }
      end)
    end
    threads.each(&:join)
    ctx = local_ctx.local
    expect(ctx.trace.length).to(eq(0))
    threads = []
    spans.each { |span| (threads << Thread.new { ctx.close_span(span) }) }
    threads.each(&:join)
  end
end
