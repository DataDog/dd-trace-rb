require('contrib/rack/helpers')
class RequestQueuingTest < RackBaseTest
  before do
    super
    Datadog.configuration[:rack][:request_queuing] = true
  end
  it('request queuing header') do
    request_start = (Time.now.utc - 5).to_i
    header('x-request-start', "t=#{request_start}")
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(2))
    rack_span = spans.find { |s| (s.name == 'rack.request') }
    frontend_span = spans.find { |s| (s.name == 'http_server.queue') }
    refute_nil(rack_span)
    refute_nil(frontend_span)
    expect(rack_span.span_type).to(eq('http'))
    expect(rack_span.service).to(eq('rack'))
    expect(rack_span.resource).to(eq('GET 200'))
    expect(rack_span.get_tag('http.method')).to(eq('GET'))
    expect(rack_span.get_tag('http.status_code')).to(eq('200'))
    expect(rack_span.get_tag('http.url')).to(eq('/success/'))
    expect(rack_span.status).to(eq(0))
    expect(rack_span.parent_id).to(eq(frontend_span.span_id))
    expect(frontend_span.service).to(eq('web-server'))
    expect(frontend_span.start_time.to_i).to(eq(request_start))
  end
  it('request alternative queuing header') do
    request_start = (Time.now.utc - 5).to_i
    header('x-queue-start', "t=#{request_start}")
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(2))
    rack_span = spans.find { |s| (s.name == 'rack.request') }
    frontend_span = spans.find { |s| (s.name == 'http_server.queue') }
    refute_nil(rack_span)
    refute_nil(frontend_span)
    expect(rack_span.span_type).to(eq('http'))
    expect(rack_span.service).to(eq('rack'))
    expect(rack_span.resource).to(eq('GET 200'))
    expect(rack_span.get_tag('http.method')).to(eq('GET'))
    expect(rack_span.get_tag('http.status_code')).to(eq('200'))
    expect(rack_span.get_tag('http.url')).to(eq('/success/'))
    expect(rack_span.status).to(eq(0))
    expect(rack_span.parent_id).to(eq(frontend_span.span_id))
    expect(frontend_span.service).to(eq('web-server'))
    expect(frontend_span.start_time.to_i).to(eq(request_start))
  end
  it('request queuing service name') do
    Datadog.configuration[:rack][:web_service_name] = 'nginx'
    request_start = (Time.now.utc - 5).to_i
    header('x-request-start', "t=#{request_start}")
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(2))
    rack_span = spans.find { |s| (s.name == 'rack.request') }
    frontend_span = spans.find { |s| (s.name == 'http_server.queue') }
    refute_nil(rack_span)
    refute_nil(frontend_span)
    expect(frontend_span.service).to(eq('nginx'))
  end
  it('clock skew') do
    request_start = (Time.now.utc + 5).to_i
    header('x-request-start', "t=#{request_start}")
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    rack_span = spans[0]
    expect(rack_span.name).to(eq('rack.request'))
  end
  it('wrong header') do
    header('x-request-start', 'something_weird')
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    rack_span = spans[0]
    expect(rack_span.name).to(eq('rack.request'))
  end
  it('enabled missing header') do
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    rack_span = spans[0]
    expect(rack_span.name).to(eq('rack.request'))
  end
end
