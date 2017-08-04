require 'time'
require 'contrib/sequel/test_helper'
require 'helper'

class SequelMiniAppTest < Minitest::Test
  def check_span_publish(span)
    assert_equal('publish', span.name)
    assert_equal('webapp', span.service)
    assert_equal('/index', span.resource)
    assert_equal(span.trace_id, span.span_id)
    assert_equal(0, span.parent_id)
  end

  def check_span_process(span, parent_id, trace_id)
    assert_equal('process', span.name)
    assert_equal('datalayer', span.service)
    assert_equal('home', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def check_span_command(span, parent_id, trace_id)
    assert_equal('sequel.query', span.name)
    assert_equal('sequel', span.service)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def test_miniapp
    sequel = Sequel.sqlite(':memory:')
    sequel.create_table(:table) do
      String :name
    end

    tracer = get_test_tracer
    pin = Datadog::Pin.get_from(sequel)
    pin.tracer = tracer

    tracer.trace('publish') do |span|
      span.service = 'webapp'
      span.resource = '/index'
      tracer.trace('process') do |subspan|
        subspan.service = 'datalayer'
        subspan.resource = 'home'
        sequel[:table].insert(name: 'data')
      end
    end

    spans = tracer.writer.spans

    assert_equal(3, spans.length)
    process, publish, sequel_cmd = spans
    check_span_publish publish
    trace_id = publish.span_id
    check_span_process process, trace_id, trace_id
    parent_id = process.span_id
    check_span_command sequel_cmd, parent_id, trace_id
  end
end
