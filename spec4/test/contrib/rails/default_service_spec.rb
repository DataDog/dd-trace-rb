require('helper')
require('contrib/rails/test_helper')
RSpec.describe(TracingDefaultService) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
    update_config(:tracer, @tracer)
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  it('test that a lone span will have rails service picked up') do
    @tracer.trace('web.request') { |span| span.resource = '/index' }
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect(span.name).to(eq('web.request'))
    expect(span.resource).to(eq('/index'))
    expect(span.service).to(eq(app_name))
  end
end
