require 'helper'
require 'ddtrace/span'
class SpanTest < Minitest::Test
  def test_span_finish
    tracer = nil
    span = Datadog::Span.new(tracer, 'my.op')
    # the start_time is not set, calling start_span with Tracer would set it
    assert_nil(span.start_time)
    assert_nil(span.end_time)
    span.finish
    # the end_time must be set
    sleep(0.001)
    assert span.end_time < Time.now.utc
    assert span.start_time <= span.end_time
    assert span.to_hash[:duration] >= 0
  end

  def test_span_finish_once
    # calling finish() multiple times doesn't have any effect
    span = Datadog::Span.new(nil, 'span.test')
    sleep(0.001)
    span.finish()
    # the end_time must be set
    end_time = span.end_time
    sleep(0.001)
    span.finish()
    assert_equal(span.end_time, end_time)
  end

  def test_span_finish_at
    # finish_at must set the right time
    span = Datadog::Span.new(nil, 'span.test')
    now = Time.now.utc
    # wait 0.01s but set the end time before the wait
    sleep(0.01)
    span.finish(now)

    # we must have a span duration lesser than the wait time
    assert_equal(span.end_time, now)
  end

  def test_span_finish_at_once
    # calling finish_at() multiple times doesn't have any effect
    span = Datadog::Span.new(nil, 'span.test')
    now = Time.now.utc
    # wait 0.01s but set the end time before the wait
    sleep(0.01)
    span.finish(now)

    # call finish again doesn't change the time
    span.finish(Time.now.utc)
    assert_equal(span.end_time, now)
  end

  def test_span_finished
    # ensure the helper return the Span status
    span = Datadog::Span.new(nil, 'span.test')
    assert !span.finished?

    # now the span must be finished
    span.finish()
    assert span.finished?
  end

  def test_span_ids
    span = Datadog::Span.new(nil, 'my.op')
    assert span.span_id
    assert span.parent_id.zero?
    assert span.trace_id != span.span_id
    assert_equal(span.name, 'my.op')
    assert span.span_id.nonzero?
    assert span.trace_id.nonzero?
  end

  def test_span_with_parent
    span = Datadog::Span.new(nil, 'my.op', parent_id: 12, trace_id: 13)
    assert span.span_id
    assert_equal(span.parent_id, 12)
    assert_equal(span.trace_id, 13)
    assert_equal(span.name, 'my.op')
  end

  def test_span_set_parent
    parent = Datadog::Span.new(nil, 'parent.span')
    child = Datadog::Span.new(nil, 'child.span')

    child.set_parent(parent)
    assert_equal(child.parent, parent)
    assert_equal(child.trace_id, parent.trace_id)
    assert_equal(child.parent_id, parent.span_id)
    assert_nil(child.service)
    assert_nil(parent.service)
  end

  def test_span_set_parent_keep_service
    parent = Datadog::Span.new(nil, 'parent.span', service: 'webapp')
    child = Datadog::Span.new(nil, 'child.span', service: 'defaultdb')

    child.set_parent(parent)
    assert_equal(child.parent, parent)
    assert_equal(child.trace_id, parent.trace_id)
    assert_equal(child.parent_id, parent.span_id)
    refute_equal(child.service, 'webapp')
    assert_equal(child.service, 'defaultdb')
  end

  def test_span_set_parent_nil
    parent = Datadog::Span.new(nil, 'parent.span', service: 'webapp')
    child = Datadog::Span.new(nil, 'child.span', service: 'defaultdb')

    child.set_parent(parent)
    child.set_parent(nil)
    assert_nil(child.parent)
    assert_equal(child.trace_id, child.span_id)
    assert_equal(child.parent_id, 0)
    assert_equal(child.service, 'defaultdb')
  end

  def test_get_valid_metric
    span = Datadog::Span.new(nil, 'test.span')
    span.set_metric('a', 10)
    assert_equal(10.0, span.get_metric('a'))
  end

  def test_set_valid_metrics
    # metrics must be converted to float values
    span = Datadog::Span.new(nil, 'test.span')
    span.set_metric('a', 0)
    span.set_metric('b', -12)
    span.set_metric('c', 12.134)
    span.set_metric('d', 1231543543265475686787869123)
    span.set_metric('e', '12.34')
    h = span.to_hash
    expected = {
      'a' => 0.0,
      'b' => -12.0,
      'c' => 12.134,
      'd' => 1231543543265475686787869123.0,
      'e' => 12.34
    }
    assert_equal(expected, h[:metrics])
  end

  def test_invalid_metrics
    # invalid values must be discarded
    span = Datadog::Span.new(nil, 'test.span')
    span.set_metric('a', nil)
    span.set_metric('b', {})
    span.set_metric('c', [])
    span.set_metric('d', span)
    span.set_metric('e', 'a_string')
    h = span.to_hash
    assert_equal({}, h[:metrics])
  end

  def test_set_error
    # rubocop:disable Layout/IndentHeredoc
    span = Datadog::Span.new(nil, 'test.span')
    error = RuntimeError.new('Something broke!')
    error.set_backtrace(%w[list of calling methods])
    displayed_backtrace = <<-BACKTRACE.chomp
list
of
calling
methods
BACKTRACE

    span.set_error(error)

    assert_equal('Something broke!', span.get_tag('error.msg'))
    assert_equal('RuntimeError', span.get_tag('error.type'))
    assert_equal(displayed_backtrace, span.get_tag('error.stack'))
  end
end
