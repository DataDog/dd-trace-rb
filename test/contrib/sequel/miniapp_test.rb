require 'time'
require 'contrib/sequel/test_helper'
require 'helper'

class SequelMiniAppTest < Minitest::Test
  def check_span_publish(span)
    assert_equal('publish', span.name)
    assert_equal('webapp', span.service)
    assert_equal('/index', span.resource)
    refute_equal(span.trace_id, span.span_id)
    assert_equal(0, span.parent_id)
  end

  def check_span_process(span, parent_id, trace_id)
    assert_equal('process', span.name)
    assert_equal('datalayer', span.service)
    assert_equal('home', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def check_span_command(span, parent_id, trace_id, resource)
    assert_equal('sequel.query', span.name)
    assert_equal('sequel', span.service)
    assert_equal('sql', span.span_type)
    assert_equal('sqlite', span.get_tag('sequel.db.vendor'))
    assert_equal(resource, span.resource)
    assert_equal(0, span.status)
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
        sequel[:table].insert(name: 'data1')
        sequel[:table].insert(name: 'data2')
        data = sequel[:table].select.to_a
        assert_equal(2, data.length)
        data.each do |row|
          assert_match(/^data.$/, row[:name])
        end
      end
    end

    spans = tracer.writer.spans

    assert_equal(6, spans.length)
    process, publish, sequel_cmd1, sequel_cmd2, sequel_cmd3, sequel_cmd4 = spans
    check_span_publish publish
    parent_id = publish.span_id
    trace_id = publish.trace_id
    check_span_process process, parent_id, trace_id
    parent_id = process.span_id
    check_span_command sequel_cmd1, parent_id, trace_id, 'INSERT INTO `table` (`name`) VALUES (?)'
    check_span_command sequel_cmd2, parent_id, trace_id, 'INSERT INTO `table` (`name`) VALUES (?)'
    check_span_command sequel_cmd3, parent_id, trace_id, 'SELECT * FROM `table`'
    check_span_command sequel_cmd4, parent_id, trace_id, 'SELECT sqlite_version()'
  end
end
