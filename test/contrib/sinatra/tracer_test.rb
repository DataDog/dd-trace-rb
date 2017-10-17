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
    Datadog.configuration.use(:sinatra, tracer: tracer, enabled: true)

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

    child1, child2, root = spans

    assert_equal('sinatra', child2.service)
    assert_equal('sinatra.render_template', child2.resource)
    assert_equal('layout', child2.get_tag('sinatra.template_name'))
    assert_equal(0, child2.status)
    assert_equal(child1, child2.parent)

    assert_equal('sinatra', child1.service)
    assert_equal('sinatra.render_template', child1.resource)
    assert_equal('msg', child1.get_tag('sinatra.template_name'))
    assert_equal(0, child1.status)
    assert_equal(root, child1.parent)

    assert_equal('sinatra', root.service)
    assert_equal('GET /template', root.resource)
    assert_equal('GET', root.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/template', root.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, root.span_type)
    assert_equal(0, root.status)
    assert_nil(root.parent)
  end

  def test_literal_template
    get '/literal-template'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(3, spans.length)

    child1, child2, root = spans

    assert_equal('sinatra', child2.service)
    assert_equal('sinatra.render_template', child2.resource)
    assert_equal('layout', child2.get_tag('sinatra.template_name'))
    assert_equal(0, child2.status)
    assert_equal(child1, child2.parent)

    assert_equal('sinatra', child1.service)
    assert_equal('sinatra.render_template', child1.resource)
    assert_nil(child1.get_tag('sinatra.template_name'))
    assert_equal(0, child1.status)
    assert_equal(root, child1.parent)

    assert_equal('sinatra', root.service)
    assert_equal('GET /literal-template', root.resource)
    assert_equal('GET', root.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/literal-template', root.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, root.span_type)
    assert_equal(0, root.status)
    assert_nil(root.parent)
  end
end
