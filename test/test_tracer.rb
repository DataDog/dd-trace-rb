

require 'helper'
require 'tracer'


class TracerTest < Minitest::Test

  def test_trace()
    tracer = get_test_tracer()

    tracer.trace("something") do |s|
      assert_equal(s.end_time, nil)
      sleep 0.1
    end

    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, "something")
  end

  def test_trace_error()
    tracer = get_test_tracer()

    tracer.trace("something") do |s|
      assert_equal(s.end_time, nil)
      1/0
    end

    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, "something")
  end




end
