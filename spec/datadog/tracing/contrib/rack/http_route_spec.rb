require 'datadog/tracing/contrib/support/spec_helper'

require 'rack/test'

require 'datadog'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack testing for http.route' do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack
    end
  end

  after do
    Datadog.configuration.tracing[:rack].reset!
  end

  let(:app) do
    app = rack_app

    Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware

      map('/') { run app }
      map('/rack') { run app }
    end.to_app
  end

  let(:rack_app) do
    Rack::Builder.new do
      map '/hello/world' do
        run ->(_env) { [200, { 'content-type' => 'text/plain' }, 'hello world'] }
      end

      map '/hello/:id' do
        run ->(_env) { [200, { 'content-type' => 'text/plain' }, "hello #{params[:id]}"] }
      end
    end
  end

  it 'sets http.route tag on request to base route' do
    response = get('/hello/world')

    expect(response).to be_ok
    expect(request_span.get_tag('http.route')).to eq('/hello/world')
  end

  it 'sets http.route tag on request to nested app route' do
    response = get('/rack/hello/world')

    expect(response).to be_ok
    expect(request_span.get_tag('http.route')).to eq('/rack/hello/world')
  end

  it 'sets no http.route tag when response status is 404' do
    response = get('/no_route')

    expect(response).to be_not_found
    expect(request_span.get_tag('http.route')).to be_nil
  end

  def request_span
    spans.detect do |span|
      span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST
    end
  end
end
