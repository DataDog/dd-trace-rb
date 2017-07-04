require 'helper'
require 'ddtrace/tracer'

# rubocop:disable Metrics/ClassLength
class TracerTest < Minitest::Test
  def test_trace
    tracer = get_test_tracer

    ret = tracer.trace('something') do |s|
      assert_equal(s.name, 'something')
      assert_nil(s.end_time)
      sleep(0.001)
      :return_val
    end

    assert_equal(ret, :return_val)

    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'something')
    assert span.to_hash[:duration] > 0
  end

  def test_trace_no_block
    tracer = get_test_tracer
    span = tracer.trace('something')

    assert !span.nil?
    assert_equal(span.name, 'something')
  end

  def test_trace_error
    tracer = get_test_tracer

    assert_raises ZeroDivisionError do
      tracer.trace('something') do |s|
        assert_nil(s.end_time)
        1 / 0
      end
    end

    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert !span.end_time.nil?
    assert_equal(span.name, 'something')
    assert_equal(span.get_tag('error.msg'), 'divided by 0')
    assert_equal(span.get_tag('error.type'), 'ZeroDivisionError')
    assert span.get_tag('error.stack').include?('dd-trace-rb')
  end

  def test_trace_child
    tracer = get_test_tracer

    # test a parent with two children
    tracer.trace('a', service: 'parent') do
      tracer.trace('b') { |s| s.set_tag('a', 'a') }
      tracer.trace('c', service: 'other') { |s| s.set_tag('b', 'b') }
    end

    spans = tracer.writer.spans()
    assert_equal(spans.length, 3)
    a, b, c = spans
    assert_equal(a.name, 'a')
    assert_equal(b.name, 'b')
    assert_equal(c.name, 'c')
    assert_equal(a.trace_id, b.trace_id)
    assert_equal(a.trace_id, c.trace_id)
    assert_equal(a.span_id, b.parent_id)
    assert_equal(a.span_id, c.parent_id)

    assert_equal(a.service, 'parent')
    assert_equal(b.service, 'parent')
    assert_equal(c.service, 'other')
  end

  def test_trace_child_finishing_after_parent
    tracer = get_test_tracer

    t1 = tracer.trace('t1')
    t1_child = tracer.trace('t1_child')
    assert_equal(t1_child.parent, t1)

    t1.finish
    t1_child.finish

    t2 = tracer.trace('t2')

    assert_nil(t2.parent)
  end

  def test_trace_no_block_not_finished
    tracer = get_test_tracer
    span = tracer.trace('something')
    assert_nil(span.end_time)
  end

  def test_set_service_info
    tracer = get_test_tracer
    tracer.set_service_info('rest-api', 'rails', 'web')
    assert_equal(tracer.services['rest-api'], 'app' => 'rails', 'app_type' => 'web')
  end

  def test_set_tags
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'component' => 'core')
    assert_equal(tracer.tags['env'], 'test')
    assert_equal(tracer.tags['component'], 'core')
  end

  def test_trace_global_tags
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'component' => 'core')
    span = tracer.trace('something')
    assert_equal(span.get_tag('env'), 'test')
    assert_equal(span.get_tag('component'), 'core')
  end

  def test_disabled_tracer
    tracer = get_test_tracer
    tracer.enabled = false
    tracer.trace('something').finish()

    spans = tracer.writer.spans()
    assert_equal(0, spans.length)
  end

  def test_configure_tracer
    tracer = get_test_tracer
    tracer.configure(enabled: false, hostname: 'agent.datadoghq.com', port: '8888')
    assert_equal(tracer.enabled, false)
    assert_equal(tracer.writer.transport.hostname, 'agent.datadoghq.com')
    assert_equal(tracer.writer.transport.port, '8888')
  end

  def test_default_service
    tracer = get_test_tracer
    assert_equal('rake_test_loader', tracer.default_service)
    old_service = tracer.default_service
    tracer.default_service = 'foo-bar'
    assert_equal('foo-bar', tracer.default_service)
    tracer.default_service = old_service
  end

  def test_active_span
    tracer = get_test_tracer
    span = tracer.trace('something')
    assert_equal(span, tracer.active_span, 'current span is active')
    assert_equal(false, tracer.active_span.finished?)
  end

  def test_trace_all_args
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'temp' => 'cool')

    yesterday = Time.now.utc - 24 * 60 * 60
    tracer.trace('op',
                 service: 'special-service',
                 resource: 'extra-resource',
                 span_type: 'my-type',
                 start_time: yesterday,
                 tags: { 'tag1' => 'value1', 'tag2' => 'value2' }) do
    end

    spans = tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('special-service', span.service)
    assert_equal('extra-resource', span.resource)
    assert_equal('my-type', span.span_type)
    assert_equal(yesterday, span.start_time)
    assert_equal({ 'env' => 'test', 'temp' => 'cool', 'tag1' => 'value1', 'tag2' => 'value2' }, span.meta)
  end

  def test_start_span_all_args
    tracer = get_test_tracer
    tracer.set_tags('env' => 'test', 'temp' => 'cool')

    yesterday = Time.now.utc - 24 * 60 * 60
    span = tracer.start_span('op',
                             service: 'special-service',
                             resource: 'extra-resource',
                             span_type: 'my-type',
                             start_time: yesterday,
                             tags: { 'tag1' => 'value1', 'tag2' => 'value2' })
    span.finish

    spans = tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('special-service', span.service)
    assert_equal('extra-resource', span.resource)
    assert_equal('my-type', span.span_type)
    assert_equal(yesterday, span.start_time)
    assert_equal({ 'env' => 'test', 'temp' => 'cool', 'tag1' => 'value1', 'tag2' => 'value2' }, span.meta)
  end

  def test_start_span_child_of_span
    tracer = get_test_tracer

    root = tracer.start_span('a')
    root.finish

    spans = tracer.writer.spans()
    assert_equal(1, spans.length)
    a = spans[0]

    tracer.trace('b') do
      span = tracer.start_span('c', child_of: root)
      span.finish
    end

    spans = tracer.writer.spans()
    assert_equal(2, spans.length)
    b, c = spans

    refute_equal(a.trace_id, b.trace_id, 'a and b do not belong to the same trace')
    refute_equal(b.trace_id, c.trace_id, 'b and c do not belong to the same trace')
    assert_equal(a.trace_id, c.trace_id, 'a and c belong to the same trace')
    assert_equal(a.span_id, c.parent_id, 'a is the parent of c')
  end

  def test_start_span_child_of_context
    tracer = get_test_tracer

    mutex = Mutex.new

    @thread_span = nil
    @thread_ctx = nil

    thread = Thread.new do
      mutex.synchronize do
        @thread_span = tracer.start_span('a')
        @thread_ctx = tracer.call_context
      end
    end

    1000.times do
      mutex.synchronize do
        break unless @thread_ctx.nil? || @thread_span.nil?
        sleep 0.001
      end
    end

    mutex.synchronize do
      refute_equal(@thread_ctx, tracer.call_context, 'thread context is different')
    end

    tracer.trace('b') do
      span = tracer.start_span('c', child_of: @thread_ctx)
      span.finish
    end

    mutex.synchronize do
      @thread_span.finish
    end

    thread.join

    @thread_span = nil
    @thread_ctx = nil

    spans = tracer.writer.spans()
    assert_equal(3, spans.length)
    a, b, c = spans
    refute_equal(a.trace_id, b.trace_id, 'a and b do not belong to the same trace')
    refute_equal(b.trace_id, c.trace_id, 'b and c do not belong to the same trace')
    assert_equal(a.trace_id, c.trace_id, 'a and c belong to the same trace')
    assert_equal(a.span_id, c.parent_id, 'a is the parent of c')
  end
end
