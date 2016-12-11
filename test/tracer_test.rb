require 'helper'
require 'ddtrace/tracer'

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
    spans.sort! { |a, b| a.name <=> b.name }
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

  def test_disabled_tracer
    tracer = get_test_tracer
    tracer.enabled = false
    tracer.trace('something').finish()

    spans = tracer.writer.spans()
    assert_equal(spans.length, 0)
  end

  def test_configure_tracer
    tracer = get_test_tracer
    tracer.configure(enabled: false, hostname: 'agent.datadoghq.com', port: '8888')
    assert_equal(tracer.enabled, false)
    assert_equal(tracer.writer.transport.hostname, 'agent.datadoghq.com')
    assert_equal(tracer.writer.transport.port, '8888')
  end
end
