require('spec_helper')
require('ddtrace/tracer')
require('ddtrace/propagation/http_propagator')
RSpec.describe Datadog::HTTPPropagator do
  it('inject!') do
    tracer = get_test_tracer
    tracer.trace('caller') do |span|
      env = { 'something' => 'alien' }
      Datadog::HTTPPropagator.inject!(span.context, env)
      expect(env).to(eq('something' => 'alien',
                        'x-datadog-trace-id' => span.trace_id.to_s,
                        'x-datadog-parent-id' => span.span_id.to_s))
      span.context.sampling_priority = 0
      Datadog::HTTPPropagator.inject!(span.context, env)
      expect(env).to(eq('something' => 'alien',
                        'x-datadog-trace-id' => span.trace_id.to_s,
                        'x-datadog-parent-id' => span.span_id.to_s,
                        'x-datadog-sampling-priority' => '0'))
      span.context.sampling_priority = nil
      Datadog::HTTPPropagator.inject!(span.context, env)
      expect(env).to(eq('something' => 'alien',
                        'x-datadog-trace-id' => span.trace_id.to_s,
                        'x-datadog-parent-id' => span.span_id.to_s))
    end
  end
  it('extract') do
    ctx = Datadog::HTTPPropagator.extract({})
    expect(ctx.trace_id).to(be_nil)
    expect(ctx.span_id).to(be_nil)
    expect(ctx.sampling_priority).to(be_nil)
    ctx = Datadog::HTTPPropagator.extract('HTTP_X_DATADOG_TRACE_ID' => '123',
                                          'HTTP_X_DATADOG_PARENT_ID' => '456')
    expect(ctx.trace_id).to(eq(123))
    expect(ctx.span_id).to(eq(456))
    expect(ctx.sampling_priority).to(be_nil)
    ctx = Datadog::HTTPPropagator.extract('HTTP_X_DATADOG_TRACE_ID' => '7',
                                          'HTTP_X_DATADOG_PARENT_ID' => '8',
                                          'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0')
    expect(ctx.trace_id).to(eq(7))
    expect(ctx.span_id).to(eq(8))
    expect(ctx.sampling_priority).to(eq(0))
  end
end
