require 'helper'
require 'ddtrace/span'

class SpanTest < Minitest::Test
  def test_span_finish
    tracer = nil
    span = Datadog::Span.new(tracer, 'my.op')
    assert span.start_time < Time.now.utc
    assert_equal(span.end_time, nil)
    span.finish
    assert span.end_time < Time.now.utc
  end

  def test_span_ids
    span = Datadog::Span.new(nil, 'my.op')
    assert span.span_id
    assert span.parent_id.zero?
    assert span.trace_id == span.span_id
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
    assert_equal(child.service, parent.service)
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
    assert_equal(child.parent, nil)
    assert_equal(child.trace_id, child.span_id)
    assert_equal(child.parent_id, 0)
    assert_equal(child.service, 'defaultdb')
  end
end
