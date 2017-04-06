require 'contrib/sinatra/tracer_test_base'

class TracerTest < TracerTestBase
  class TracerTestApp < Sinatra::Application
    get '/request' do
      'hello world'
    end

    get '/bad-request' do
      halt 400, 'bad request'
    end

    get '/error' do
      halt 500, 'server error'
    end

    get '/exception' do
      raise StandardError, 'something bad'
    end

    get '/wildcard/*' do
      params['splat'][0]
    end

    get '/template' do
      erb :msg, locals: { msg: 'hello' }
    end

    get '/literal-template' do
      erb '<%= msg %>', locals: { msg: 'hello' }
    end
  end

  def app
    TracerTestApp
  end

  def setup
    @writer = FauxWriter.new()
    app().set :datadog_test_writer, @writer

    tracer = Datadog::Tracer.new(writer: @writer)
    app().settings.datadog_tracer.configure(tracer: tracer, enabled: true)

    super
  end

  def test_request
    get '/request#foo?a=1'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /request', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_bad_request
    get '/bad-request'
    assert_equal(400, last_response.status)

    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /bad-request', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/bad-request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_nil(span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_nil(span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_error
    get '/error'
    assert_equal(500, last_response.status)

    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /error', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/error', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_nil(span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_nil(span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_exception
    get '/exception'
    assert_equal(500, last_response.status)

    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /exception', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/exception', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal('StandardError', span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_equal('something bad', span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(1, span.status)
    assert_nil(span.parent)
  end

  def test_wildcard
    get '/wildcard/1/2/3'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('GET /wildcard/*', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/wildcard/1/2/3', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_template
    get '/template'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(3, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('sinatra.render_template', span.resource)
    assert_equal('layout', span.get_tag('sinatra.template_name'))
    assert_equal(0, span.status)
    assert_equal(spans[1], span.parent)

    span = spans[1]
    assert_equal('sinatra', span.service)
    assert_equal('sinatra.render_template', span.resource)
    assert_equal('msg', span.get_tag('sinatra.template_name'))
    assert_equal(0, span.status)
    assert_equal(spans[2], span.parent)

    span = spans[2]
    assert_equal('sinatra', span.service)
    assert_equal('GET /template', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/template', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  def test_literal_template
    get '/literal-template'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(3, spans.length)

    span = spans[0]
    assert_equal('sinatra', span.service)
    assert_equal('sinatra.render_template', span.resource)
    assert_equal('layout', span.get_tag('sinatra.template_name'))
    assert_equal(0, span.status)
    assert_equal(spans[1], span.parent)

    span = spans[1]
    assert_equal('sinatra', span.service)
    assert_equal('sinatra.render_template', span.resource)
    assert_nil(span.get_tag('sinatra.template_name'))
    assert_equal(0, span.status)
    assert_equal(spans[2], span.parent)

    span = spans[2]
    assert_equal('sinatra', span.service)
    assert_equal('GET /literal-template', span.resource)
    assert_equal('GET', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/literal-template', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end
end
