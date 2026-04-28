require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'
require 'rack'
require 'rack/events'
require 'datadog'
require 'datadog/tracing/contrib/rack/event_handler'

RSpec.describe Datadog::Tracing::Contrib::Rack::EventHandler do
  include Rack::Test::Methods

  subject(:handler) { described_class.new }

  let(:rack_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack, rack_options
    end
  end

  after do
    Datadog.registry[:rack].reset_configuration!
  end

  describe 'implements Rack::Events::Abstract' do
    it { is_expected.to respond_to(:on_start) }
    it { is_expected.to respond_to(:on_commit) }
    it { is_expected.to respond_to(:on_send) }
    it { is_expected.to respond_to(:on_finish) }
    it { is_expected.to respond_to(:on_error) }
  end

  context 'as a Rack::Events handler' do
    let(:app) do
      the_handler = handler
      app_routes = routes

      Rack::Builder.new do
        use Rack::Events, [the_handler]
        instance_eval(&app_routes)
      end.to_app
    end

    shared_examples 'a rack.request span' do
      it 'creates a rack.request span' do
        expect(span.name).to eq('rack.request')
        expect(span.type).to eq('web')
        expect(span.service).to eq(tracer.default_service)
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
        expect(span.get_tag('span.kind')).to eq('server')
        expect(span).to be_root_span
      end
    end

    context 'with a successful request' do
      let(:routes) do
        proc { run(proc { |_env| [200, {'Content-Type' => 'text/html'}, ['OK']] }) }
      end

      before { get '/' }

      it_behaves_like 'a rack.request span'

      it 'sets HTTP tags' do
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.resource).to eq('GET 200')
        expect(span.status).to eq(0)
      end
    end

    context 'with a 404 response' do
      let(:routes) do
        proc { run(proc { |_env| [404, {'Content-Type' => 'text/html'}, ['Not Found']] }) }
      end

      before { get '/missing' }

      it_behaves_like 'a rack.request span'

      it 'records the 404 status without marking the span as error' do
        expect(span.get_tag('http.status_code')).to eq('404')
        expect(span.status).to eq(0)
      end
    end

    context 'with a 500 response' do
      let(:routes) do
        proc { run(proc { |_env| [500, {'Content-Type' => 'text/html'}, ['Error']] }) }
      end

      before { get '/' }

      it 'marks the span as an error' do
        expect(span.get_tag('http.status_code')).to eq('500')
        expect(span.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
      end
    end

    context 'when the app raises a StandardError' do
      let(:routes) do
        proc { run(proc { |_env| raise 'boom' }) }
      end

      before { get '/' rescue nil } # rubocop:disable Style/RescueModifier

      it_behaves_like 'a rack.request span'

      it 'records the error on the span' do
        expect(span.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to eq('RuntimeError')
      end
    end

    context 'with distributed tracing enabled' do
      let(:rack_options) { {distributed_tracing: true} }
      let(:routes) do
        proc { run(proc { |_env| [200, {}, ['OK']] }) }
      end

      before do
        get '/', {}, {
          'HTTP_X_DATADOG_TRACE_ID' => '1234',
          'HTTP_X_DATADOG_PARENT_ID' => '5678',
          'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1',
        }
      end

      it 'continues the distributed trace' do
        expect(span.trace_id).to eq(1234)
        expect(span.parent_id).to eq(5678)
      end
    end

    context 'with distributed tracing disabled' do
      let(:rack_options) { {distributed_tracing: false} }
      let(:routes) do
        proc { run(proc { |_env| [200, {}, ['OK']] }) }
      end

      before do
        get '/', {}, {
          'HTTP_X_DATADOG_TRACE_ID' => '1234',
          'HTTP_X_DATADOG_PARENT_ID' => '5678',
        }
      end

      it 'does not continue the distributed trace' do
        expect(span.trace_id).not_to eq(1234)
      end
    end

    context 'with request queuing enabled' do
      let(:rack_options) { {request_queuing: true} }
      let(:routes) do
        proc { run(proc { |_env| [200, {}, ['OK']] }) }
      end

      before do
        get '/', {}, {'HTTP_X_REQUEST_START' => "t=#{(Time.now.to_f - 0.5).round(3)}"}
      end

      it 'creates proxy spans alongside the request span' do
        expect(spans.map(&:name)).to include('http.proxy.request', 'http.proxy.queue', 'rack.request')
      end

      it 'finishes all spans' do
        expect(spans).to all(be_finished)
      end
    end

    context 'with rack-in-rack (outer TraceMiddleware, inner EventHandler)' do
      let(:inner_app) do
        the_handler = handler
        Rack::Builder.new do
          use Rack::Events, [the_handler]
          run(proc { |_env| [200, {}, ['inner']] })
        end.to_app
      end

      let(:app) do
        inner = inner_app
        Rack::Builder.new do
          use Datadog::Tracing::Contrib::Rack::TraceMiddleware
          run inner
        end.to_app
      end

      before do
        require 'datadog/tracing/contrib/rack/middlewares'
        get '/'
      end

      it 'creates only one rack.request span' do
        rack_spans = spans.select { |s| s.name == 'rack.request' }
        expect(rack_spans).to have(1).item
      end

      it 'the span comes from the outer TraceMiddleware' do
        expect(span).to be_root_span
        expect(span.name).to eq('rack.request')
      end
    end

    context 'with rack-in-rack (outer EventHandler, inner EventHandler)' do
      let(:inner_app) do
        Rack::Builder.new do
          use Rack::Events, [Datadog::Tracing::Contrib::Rack::EventHandler.new]
          run(proc { |_env| [200, {}, ['inner']] })
        end.to_app
      end

      let(:app) do
        inner = inner_app
        the_handler = handler
        Rack::Builder.new do
          use Rack::Events, [the_handler]
          run inner
        end.to_app
      end

      before { get '/' }

      it 'creates only one rack.request span' do
        rack_spans = spans.select { |s| s.name == 'rack.request' }
        expect(rack_spans).to have(1).item
      end
    end

    context 'with response headers configured' do
      let(:rack_options) { {headers: {response: ['X-Custom-Header']}} }
      let(:routes) do
        proc { run(proc { |_env| [200, {'X-Custom-Header' => 'custom-value'}, ['OK']] }) }
      end

      before { get '/' }

      it 'tags the configured response header' do
        expect(span.get_tag('http.response.headers.x-custom-header')).to eq('custom-value')
      end
    end
  end

  describe '#on_start' do
    let(:env) { {'rack.url_scheme' => 'http', 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/'} }
    let(:request) { Rack::Request.new(env) }

    it 'opens a rack.request span and stores it in env' do
      handler.on_start(request, nil)
      expect(env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]).not_to be_nil
    ensure
      env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]&.finish
    end

    it 'marks the handler as active in env' do
      handler.on_start(request, nil)
      expect(env[described_class::RACK_ENV_ACTIVE]).to be(true)
    ensure
      env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]&.finish
    end

    context 'when rack-in-rack (span already set)' do
      before do
        env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = instance_double(
          Datadog::Tracing::SpanOperation
        )
      end

      it 'does not open a new span' do
        expect(Datadog::Tracing).not_to receive(:trace)
        handler.on_start(request, nil)
      end

      it 'does not mark handler as active' do
        handler.on_start(request, nil)
        expect(env[described_class::RACK_ENV_ACTIVE]).to be_nil
      end
    end
  end

  describe '#on_finish' do
    let(:env) do
      {
        'rack.url_scheme' => 'http',
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/',
        'QUERY_STRING' => '',
        'SCRIPT_NAME' => '',
        'SERVER_NAME' => 'example.org',
        'SERVER_PORT' => '80',
        'HTTP_HOST' => 'example.org',
      }
    end
    let(:request) { Rack::Request.new(env) }
    let(:response) do
      instance_double(Rack::Events::BufferedResponse, status: 200, headers: {'Content-Type' => 'text/html'})
    end

    before { handler.on_start(request, nil) }

    it 'finishes the span' do
      span = env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
      handler.on_finish(request, response)
      expect(span).to be_finished
    end

    it 'clears the active marker from env' do
      handler.on_finish(request, response)
      expect(env[described_class::RACK_ENV_ACTIVE]).to be_nil
    end

    context 'when called without a prior on_start (rack-in-rack)' do
      let(:foreign_span) { instance_double(Datadog::Tracing::SpanOperation) }

      before do
        env.delete(described_class::RACK_ENV_ACTIVE)
        env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = foreign_span
      end

      it 'does not finish the foreign span' do
        expect(foreign_span).not_to receive(:finish)
        handler.on_finish(request, response)
      end
    end

    context 'with a nil response (error path)' do
      it 'finishes the span without raising' do
        span = env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
        expect { handler.on_finish(request, nil) }.not_to raise_error
        expect(span).to be_finished
      end
    end
  end

  describe '#on_error' do
    let(:env) do
      {
        'rack.url_scheme' => 'http',
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/',
      }
    end
    let(:request) { Rack::Request.new(env) }
    let(:error) { RuntimeError.new('something went wrong') }

    before { handler.on_start(request, nil) }

    it 'sets the error on the span without finishing it' do
      span = env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
      handler.on_error(request, nil, error)
      expect(span.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
      expect(span).not_to be_finished
    ensure
      span&.finish
    end

    context 'when rack-in-rack (handler not active)' do
      let(:foreign_span) { instance_double(Datadog::Tracing::SpanOperation) }

      before do
        env.delete(described_class::RACK_ENV_ACTIVE)
        env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = foreign_span
      end

      it 'does not touch the foreign span' do
        expect(foreign_span).not_to receive(:set_error)
        handler.on_error(request, nil, error)
      end
    end
  end
end
