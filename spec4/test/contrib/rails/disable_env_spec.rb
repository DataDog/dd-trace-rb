ENV['DISABLE_DATADOG_RAILS'] = '1'
require('helper')
require('contrib/rails/test_helper')
RSpec.describe(TracingController) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  it('rails must not be instrumented') do
    get(:index)
    assert_response(:success)
    spans = @tracer.writer.spans
    expect(0).to(eq(spans.length))
  end
  it('manual instrumentation should still work') do
    @tracer.trace('a-test') { true }
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
  end
end
