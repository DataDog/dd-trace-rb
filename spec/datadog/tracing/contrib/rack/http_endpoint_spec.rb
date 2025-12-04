require 'datadog/tracing/contrib/support/spec_helper'

require 'rack/test'
require 'rack/builder'

require 'datadog'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack testing for http.endpoint tag' do
  include Rack::Test::Methods

  around(:suite) do |example|
    Datadog.configure do |c|
      c.tracing.instrument :rack
    end

    example.run
  ensure
    Datadog.configuration.tracing[:rack].reset!
    Datadog.configuration.tracing.resource_renaming.reset!
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
        run ->(_env) { [200, {'content-type' => 'text/plain'}, 'hello world'] }
      end

      map '/hello/:id' do
        run ->(_env) { [200, {'content-type' => 'text/plain'}, "hello #{params[:id]}"] }
      end
    end
  end

  let(:request_span) do
    spans.find do |span|
      span.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST
    end
  end

  context 'when resource_renaming.enabled is disabled by default and appsec is enabled' do
    before do
      Datadog.configuration.appsec.enabled = true
      Datadog.configuration.tracing.resource_renaming.reset!
    end

    after do
      Datadog.configuration.appsec.reset!
    end

    it 'sets http.endpoint tag on request to base route' do
      response = get('/hello/world')

      expect(response).to be_ok
      expect(request_span.get_tag('http.endpoint')).to eq('/hello/world')
    end
  end

  context 'when resource_renaming.enabled is explicitly set to false and appsec is enabled' do
    before do
      Datadog.configuration.appsec.enabled = true
      Datadog.configuration.tracing.resource_renaming.enabled = false
    end

    after do
      Datadog.configuration.appsec.reset!
    end

    it 'does not report http.endpoint' do
      response = get('/hello/world')

      expect(response).to be_ok
      expect(request_span.tags).not_to have_key('http.endpoint')
    end
  end

  context 'when resource_renaming.enabled is set to true' do
    before do
      Datadog.configuration.tracing.resource_renaming.enabled = true
    end

    it 'sets http.endpoint tag on request to base route' do
      response = get('/hello/world')

      expect(response).to be_ok
      expect(request_span.get_tag('http.endpoint')).to eq('/hello/world')
    end

    it 'sets http.endpoint tag on request to nested app route' do
      response = get('/rack/hello/world')

      expect(response).to be_ok
      expect(request_span.get_tag('http.endpoint')).to eq('/rack/hello/world')
    end

    it 'sets no http.endpoint tag when response status is 404' do
      response = get('/no_route')

      expect(response).to be_not_found
      expect(request_span.get_tag('http.endpoint')).to be_nil
    end
  end
end
