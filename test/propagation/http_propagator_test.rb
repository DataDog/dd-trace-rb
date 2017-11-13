require 'helper'
require 'ddtrace/tracer'
require 'ddtrace/propagation/http_propagator'

class HTTPPropagatorTest < Minitest::Test
  def test_inject!
    tracer = get_test_tracer

    tracer.trace('caller') do |span|
      env = { 'something' => 'alien' }
      Datadog::HTTPPropagator.inject!(span, env)
      assert_equal({ 'something' => 'alien',
                     'x-datadog-trace-id' => span.trace_id.to_s,
                     'x-datadog-parent-id' => span.span_id.to_s }, env)
      span.sampling_priority = 0
      Datadog::HTTPPropagator.inject!(span, env)
      assert_equal({ 'something' => 'alien',
                     'x-datadog-trace-id' => span.trace_id.to_s,
                     'x-datadog-parent-id' => span.span_id.to_s,
                     'x-datadog-sampling-priority' => '0' }, env)
      span.sampling_priority = nil
      Datadog::HTTPPropagator.inject!(span, env)
      assert_equal({ 'something' => 'alien',
                     'x-datadog-trace-id' => span.trace_id.to_s,
                     'x-datadog-parent-id' => span.span_id.to_s }, env)
    end
  end

  def test_extract
    ctx = Datadog::HTTPPropagator.extract({})
    assert_nil(ctx.trace_id)
    assert_nil(ctx.span_id)
    assert_nil(ctx.sampling_priority)
    ctx = Datadog::HTTPPropagator.extract('HTTP_X_DATADOG_TRACE_ID' => '123',
                                          'HTTP_X_DATADOG_PARENT_ID' => '456')
    assert_equal(123, ctx.trace_id)
    assert_equal(456, ctx.span_id)
    assert_nil(ctx.sampling_priority)
    ctx = Datadog::HTTPPropagator.extract('HTTP_X_DATADOG_TRACE_ID' => '7',
                                          'HTTP_X_DATADOG_PARENT_ID' => '8',
                                          'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0')
    assert_equal(7, ctx.trace_id)
    assert_equal(8, ctx.span_id)
    assert_equal(0, ctx.sampling_priority)
  end
end
