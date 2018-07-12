require('securerandom')
require('contrib/rack/helpers')
require('rails_helper')

RSpec.describe('Rack middleware') do
  it('request middleware get') do
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware get without request uri') do
    get('/success?foo=bar')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware get with request uri') do
    get('/success?foo=bar', {}, 'REQUEST_URI' => '/success?foo=bar')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success?foo'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware get with request uri and quantize option') do
    Datadog.configure do |c|
      c.use(:rack, quantize: { query: { show: ['foo'] } })
    end
    get('/success?foo=bar', {}, 'REQUEST_URI' => '/success?foo=bar')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success?foo=bar'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware post') do
    post('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('POST 200'))
    expect(span.get_tag('http.method')).to(eq('POST'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware routes') do
    get('/success/100')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success/100'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware missing application') do
    get('/not/exists/')
    expect(last_response.not_found?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 404'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('404'))
    expect(span.get_tag('http.url')).to(eq('/not/exists/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware bad request') do
    get('/failure/')
    expect((last_response.status == 400)).to(be_truthy)
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 400'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('400'))
    expect(span.get_tag('http.url')).to(eq('/failure/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware exception') do
    expect { get('/exception/') }.to(raise_error)
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(be_nil)
    expect(span.get_tag('http.url')).to(eq('/exception/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.get_tag('error.type')).to(eq('StandardError'))
    expect(span.get_tag('error.msg')).to(eq('Unable to process the request'))
    refute_nil(span.get_tag('error.stack'))
    expect(span.status).to(eq(1))
    expect(span.parent).to(be_nil)
  end
  it('request middleware rack app') do
    get('/app/posts/100')
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET /app/'))
    expect(span.get_tag('http.method')).to(eq('GET_V2'))
    expect(span.get_tag('http.status_code')).to(eq('201'))
    expect(span.get_tag('http.url')).to(eq('/app/static/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware 500') do
    get('/500/')
    expect((last_response.status == 500)).to(be_truthy)
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 500'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('500'))
    expect(span.get_tag('http.url')).to(eq('/500/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.get_tag('error.stack')).to(be_nil)
    expect(span.status).to(eq(1))
    expect(span.parent).to(be_nil)
  end
  it('request middleware 500 handled') do
    get('/app/500/')
    expect((last_response.status == 500)).to(be_truthy)
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 500'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('500'))
    expect(span.get_tag('http.url')).to(eq('/app/500/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(1))
    expect(span.get_tag('error.stack')).to(eq('Handled exception'))
    expect(span.parent).to(be_nil)
  end
  it('request middleware 500 handled without status') do
    get('/app/500/no_status/')
    expect((last_response.status == 500)).to(be_truthy)
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 500'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('500'))
    expect(span.get_tag('http.url')).to(eq('/app/500/no_status/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(1))
    expect(span.get_tag('error.stack')).to(eq('Handled exception'))
    expect(span.parent).to(be_nil)
  end
  it('request middleware non standard error') do
    expect { get('/nomemory/') }.to(raise_error(NoMemoryError))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(be_nil)
    expect(span.get_tag('http.url')).to(eq('/nomemory/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.get_tag('error.type')).to(eq('NoMemoryError'))
    expect(span.get_tag('error.msg')).to(eq('Non-standard error'))
    refute_nil(span.get_tag('error.stack'))
    expect(span.status).to(eq(1))
    expect(span.parent).to(be_nil)
  end
  it('middleware context cleaning') do
    get('/leak')
    get('/success')
    expect(@tracer.provider.context.trace.length).to(eq(0))
    expect(@tracer.writer.spans.length).to(eq(1))
  end
  it('request middleware custom service') do
    Datadog.configure { |c| c.use(:rack, service_name: 'custom-rack') }
    get('/success/')
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('custom-rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/success/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('request middleware headers') do
    Datadog.configure do |c|
      c.use(:rack,
            headers: { request: ['Cache-Control'],
                       response: %w[Content-Type Cache-Control Content-Type ETag Expires Last-Modified X-Request-Id] })
    end
    request_headers = { 'HTTP_CACHE_CONTROL' => 'no-cache',
                        'HTTP_X_REQUEST_ID' => SecureRandom.uuid,
                        'HTTP_X_FAKE_REQUEST' => "Don't tag me." }
    get('/headers/', {}, request_headers)
    expect(last_response.ok?).to(eq(true))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans.first
    expect(span.name).to(eq('rack.request'))
    expect(span.span_type).to(eq('http'))
    expect(span.service).to(eq('rack'))
    expect(span.resource).to(eq('GET 200'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('http.url')).to(eq('/headers/'))
    expect(span.get_tag('http.base_url')).to(eq('http://example.org'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
    expect(span.get_tag('http.request.headers.cache_control')).to(eq('no-cache'))
    expect(span.get_tag('http.request.headers.x_request_id')).to(be_nil)
    expect(span.get_tag('http.request.headers.x_fake_request')).to(be_nil)
    expect(span.get_tag('http.response.headers.content_type')).to(eq('text/html'))
    expect(span.get_tag('http.response.headers.cache_control')).to(eq('max-age=3600'))
    expect(span.get_tag('http.response.headers.etag')).to(eq('"737060cd8c284d8af7ad3082f209582d"'))
    expect(span.get_tag('http.response.headers.last_modified')).to(eq('Tue, 15 Nov 1994 12:45:26 GMT'))
    expect(span.get_tag('http.response.headers.x_request_id')).to(eq('f058ebd6-02f7-4d3f-942e-904344e8cde5'))
    expect(span.get_tag('http.request.headers.x_fake_response')).to(be_nil)
  end
end
