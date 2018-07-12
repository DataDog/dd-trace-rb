require('contrib/sinatra/tracer_test_base')
require 'spec_helper'

class TracerTestApp < Sinatra::Application
  get('/request') do
    headers['X-Request-Id'] = request.env['HTTP_X_REQUEST_ID']
    'hello world'
  end
  get('/bad-request') { halt(400, 'bad request') }
  get('/error') { halt(500, 'server error') }
  get('/exception') { raise(StandardError, 'something bad') }
  get('/wildcard/*') { params['splat'][0] }
  get('/template') { erb(:msg, locals: { msg: 'hello' }) }
  get('/literal-template') do
    erb('<%= msg %>', locals: { msg: 'hello' })
  end
end

RSpec.describe 'Sinatra tracer' do
  def app
    TracerTestApp
  end

  before do
    @writer = FauxWriter.new
    app.set(:datadog_test_writer, @writer)
    tracer = Datadog::Tracer.new(writer: @writer, enabled: true)
    Datadog.configuration.use(:sinatra, tracer: tracer)
    super
  end

  it('service name') do
    begin
      (previous_name = Datadog.configuration[:sinatra][:service_name]
       Datadog.configuration.use(:sinatra, service_name: 'my-sinatra-app')
       get('/request')
       expect(last_response.status).to(eq(200))
       spans = @writer.spans
       expect(spans.length).to(eq(1))
       span = spans[0]
       expect(span.service).to(eq('my-sinatra-app')))
    ensure
      Datadog.configuration.use(:sinatra, service_name: previous_name)
    end
  end
  it('request') do
    get('/request#foo?a=1')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sinatra'))
    expect(span.resource).to(eq('GET /request'))
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/request'))
    expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('distributed request') do
    begin
      (Datadog.configuration.use(:sinatra, distributed_tracing: true)
       response = get('/request', {},
                      'HTTP_X_DATADOG_TRACE_ID' => '1',
                      'HTTP_X_DATADOG_PARENT_ID' => '2',
                      'HTTP_X_DATADOG_SAMPLING_PRIORITY' => Datadog::Ext::Priority::USER_KEEP.to_s)
       expect(response.status).to(eq(200))
       spans = @writer.spans
       expect(spans.length).to(eq(1))
       span = spans[0]
       expect(span.trace_id).to(eq(1))
       expect(span.parent_id).to(eq(2))
       expect(span.get_metric('_sampling_priority_v1')).to(eq(2.0)))
    ensure
      Datadog.configuration.use(:sinatra, distributed_tracing: false)
    end
  end
  it('bad request') do
    get('/bad-request')
    expect(last_response.status).to(eq(400))
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sinatra'))
    expect(span.resource).to(eq('GET /bad-request'))
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/bad-request'))
    expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to(be_nil)
    expect(span.get_tag(Datadog::Ext::Errors::MSG)).to(be_nil)
    expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('error') do
    get('/error')
    expect(last_response.status).to(eq(500))
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sinatra'))
    expect(span.resource).to(eq('GET /error'))
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/error'))
    expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to(be_nil)
    expect(span.get_tag(Datadog::Ext::Errors::MSG)).to(be_nil)
    expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(span.status).to(eq(1))
    expect(span.parent).to(be_nil)
  end
  it('exception') do
    get('/exception')
    expect(last_response.status).to(eq(500))
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sinatra'))
    expect(span.resource).to(eq('GET /exception'))
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/exception'))
    expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to(eq('StandardError'))
    expect(span.get_tag(Datadog::Ext::Errors::MSG)).to(eq('something bad'))
    expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(span.status).to(eq(1))
    expect(span.parent).to(be_nil)
  end
  it('wildcard') do
    get('/wildcard/1/2/3')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sinatra'))
    expect(span.resource).to(eq('GET /wildcard/*'))
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/wildcard/1/2/3'))
    expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('template') do
    get('/template')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(3))
    child1, child2, root = spans
    expect(child2.service).to(eq('sinatra'))
    expect(child2.resource).to(eq('sinatra.render_template'))
    expect(child2.get_tag('sinatra.template_name')).to(eq('layout'))
    expect(child2.status).to(eq(0))
    expect(child2.parent).to(eq(child1))
    expect(child1.service).to(eq('sinatra'))
    expect(child1.resource).to(eq('sinatra.render_template'))
    expect(child1.get_tag('sinatra.template_name')).to(eq('msg'))
    expect(child1.status).to(eq(0))
    expect(child1.parent).to(eq(root))
    expect(root.service).to(eq('sinatra'))
    expect(root.resource).to(eq('GET /template'))
    expect(root.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(root.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/template'))
    expect(root.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(root.status).to(eq(0))
    expect(root.parent).to(be_nil)
  end
  it('literal template') do
    get('/literal-template')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(3))
    child1, child2, root = spans
    expect(child2.service).to(eq('sinatra'))
    expect(child2.resource).to(eq('sinatra.render_template'))
    expect(child2.get_tag('sinatra.template_name')).to(eq('layout'))
    expect(child2.status).to(eq(0))
    expect(child2.parent).to(eq(child1))
    expect(child1.service).to(eq('sinatra'))
    expect(child1.resource).to(eq('sinatra.render_template'))
    expect(child1.get_tag('sinatra.template_name')).to(be_nil)
    expect(child1.status).to(eq(0))
    expect(child1.parent).to(eq(root))
    expect(root.service).to(eq('sinatra'))
    expect(root.resource).to(eq('GET /literal-template'))
    expect(root.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(root.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/literal-template'))
    expect(root.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(root.status).to(eq(0))
    expect(root.parent).to(be_nil)
  end
  it('tagging default connection headers') do
    request_id = SecureRandom.uuid
    get('/request', {}, 'HTTP_X_REQUEST_ID' => request_id)
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sinatra'))
    expect(span.resource).to(eq('GET /request'))
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/request'))
    expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(span.get_tag('http.response.headers.x_request_id')).to(eq(request_id))
    expect(span.get_tag('http.response.headers.content_type')).to(eq('text/html;charset=utf-8'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('tagging configured connection headers') do
    begin
      (Datadog.configuration.use(:sinatra, headers: { response: ['Content-Type'], request: ['X-Request-Header'] })
       request_headers = { 'HTTP_X_REQUEST_HEADER' => 'header_value', 'HTTP_X_HEADER' => "don't tag me" }
       get('/request#foo?a=1', {}, request_headers)
       expect(last_response.status).to(eq(200))
       spans = @writer.spans
       expect(spans.length).to(eq(1))
       span = spans[0]
       expect(span.service).to(eq('sinatra'))
       expect(span.resource).to(eq('GET /request'))
       expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('GET'))
       expect(span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/request'))
       expect(span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
       expect(span.get_tag('http.request.headers.x_request_header')).to(eq('header_value'))
       expect(span.get_tag('http.response.headers.content_type')).to(eq('text/html;charset=utf-8'))
       expect(span.get_tag('http.request.headers.x_header')).to(be_nil)
       expect(span.status).to(eq(0))
       expect(span.parent).to(be_nil))
    ensure
      Datadog.configuration.use(:sinatra, headers: Datadog::Contrib::Sinatra::Tracer::DEFAULT_HEADERS)
    end
  end
end
