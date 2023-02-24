require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'
require 'securerandom'
require 'rack'
require 'ddtrace'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  let(:rack_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack, rack_options
    end
  end

  after { Datadog.registry[:rack].reset_configuration! }

  shared_examples 'a rack GET 200 span' do
    it do
      expect(span.name).to eq('rack.request')
      expect(span.span_type).to eq('web')
      expect(span.service).to eq(tracer.default_service)
      expect(span.resource).to eq('GET 200')
      expect(span.get_tag('http.method')).to eq('GET')
      expect(span.get_tag('http.status_code')).to eq('200')
      expect(span.status).to eq(0)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
      expect(span.get_tag('span.kind')).to eq('server')
    end
  end

  context 'for an application' do
    let(:app) do
      app_routes = routes

      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware
        instance_eval(&app_routes)
      end.to_app
    end

    context 'with no routes' do
      # NOTE: Have to give a Rack app at least one route.
      let(:routes) do
        proc do
          map '/no/routes' do
            run(proc { |_env| })
          end
        end
      end

      before do
        is_expected.to be_not_found
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get '/not/exists/' }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq(Datadog.configuration.service)
          expect(span.resource).to eq('GET 404')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('404')
          expect(span.get_tag('http.url')).to eq('/not/exists/')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.status).to eq(0)
          expect(span).to be_root_span
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq('rack')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('request')
          expect(span.get_tag('span.kind'))
            .to eq('server')
        end
      end
    end

    context 'with a basic route' do
      let(:routes) do
        proc do
          map '/success/' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
          end
        end
      end

      before do
        is_expected.to be_ok
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get route }

        context 'without parameters' do
          let(:route) { '/success/' }

          it_behaves_like 'a rack GET 200 span'

          context 'and default quantization' do
            let(:rack_options) { { quantize: {} } }

            it do
              expect(span.get_tag('http.url')).to eq('/success/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end

          context 'and quantization activated for URL base' do
            let(:rack_options) { { quantize: { base: :show } } }

            it do
              expect(span.get_tag('http.url')).to eq('http://example.org/success/')
              expect(span.get_tag('http.base_url')).to be_nil
              expect(span).to be_root_span
            end
          end

          it { expect(trace.resource).to eq('GET 200') }
        end

        context 'with query string parameters' do
          let(:route) { '/success?foo=bar' }

          context 'and default quantization' do
            let(:rack_options) { { quantize: {} } }

            it_behaves_like 'a rack GET 200 span'

            it do
              expect(span.get_tag('http.url')).to eq('/success?foo')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end

          context 'and quantization activated for the query' do
            let(:rack_options) { { quantize: { query: { show: ['foo'] } } } }

            it_behaves_like 'a rack GET 200 span'

            it do
              expect(span.get_tag('http.url')).to eq('/success?foo=bar')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end
        end

        context 'with REQUEST_URI being a path' do
          subject(:response) { get '/success?foo=bar', {}, 'REQUEST_URI' => '/success?foo=bar' }

          context 'and default quantization' do
            let(:rack_options) { { quantize: {} } }

            it_behaves_like 'a rack GET 200 span'

            it do
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # However, that query string will be quantized.
              expect(span.get_tag('http.url')).to eq('/success?foo')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end

          context 'and quantization activated for the query' do
            let(:rack_options) { { quantize: { query: { show: ['foo'] } } } }

            it_behaves_like 'a rack GET 200 span'

            it do
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # The query string will not be quantized, per the option.
              expect(span.get_tag('http.url')).to eq('/success?foo=bar')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end

          context 'and quantization activated for base' do
            let(:rack_options) { { quantize: { base: :show } } }

            it_behaves_like 'a rack GET 200 span'

            it do
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # The query string will not be quantized, per the option.
              expect(span.get_tag('http.url')).to eq('http://example.org/success?foo')
              expect(span.get_tag('http.base_url')).to be_nil
              expect(span).to be_root_span
            end
          end
        end

        context 'with REQUEST_URI containing base URI' do
          subject(:response) { get '/success?foo=bar', {}, 'REQUEST_URI' => 'http://example.org/success?foo=bar' }

          context 'and default quantization' do
            let(:rack_options) { { quantize: {} } }

            it_behaves_like 'a rack GET 200 span'

            it do
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # However, that query string will be quantized.
              expect(span.get_tag('http.url')).to eq('/success?foo')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end

          context 'and quantization activated for the query' do
            let(:rack_options) { { quantize: { query: { show: ['foo'] } } } }

            it_behaves_like 'a rack GET 200 span'

            it do
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # The query string will not be quantized, per the option.
              expect(span.get_tag('http.url')).to eq('/success?foo=bar')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span
            end
          end

          context 'and quantization activated for base' do
            let(:rack_options) { { quantize: { base: :show } } }

            it_behaves_like 'a rack GET 200 span'

            it do
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # The query string will not be quantized, per the option.
              expect(span.get_tag('http.url')).to eq('http://example.org/success?foo')
              expect(span.get_tag('http.base_url')).to be_nil
              expect(span).to be_root_span
            end
          end
        end

        context 'with sub-route' do
          let(:route) { '/success/100' }

          it_behaves_like 'a rack GET 200 span'

          it do
            expect(span.get_tag('http.url')).to eq('/success/100')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span).to be_root_span
          end
        end
      end

      describe 'POST request' do
        subject(:response) { post route }

        context 'without parameters' do
          let(:route) { '/success/' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq(Datadog.configuration.service)
            expect(span.resource).to eq('POST 200')
            expect(span.get_tag('http.method')).to eq('POST')
            expect(span.get_tag('http.status_code')).to eq('200')
            expect(span.get_tag('http.url')).to eq('/success/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.status).to eq(0)
            expect(span).to be_root_span
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq('rack')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('request')
            expect(span.get_tag('span.kind'))
              .to eq('server')
          end
        end
      end
    end

    context 'when `request_queuing` enabled' do
      let(:routes) do
        proc do
          map '/request_queuing_enabled' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
          end
        end
      end

      describe 'when request queueing includes the request time' do
        let(:rack_options) { { request_queuing: :include_request } }

        it 'creates web_server_span and rack span' do
          get 'request_queuing_enabled',
            nil,
            { Datadog::Tracing::Contrib::Rack::QueueTime::REQUEST_START => "t=#{Time.now.to_f}" }

          expect(trace.resource).to eq('GET 200')

          expect(spans).to have(2).items

          server_queue_span = spans[0]
          rack_span = spans[1]

          expect(server_queue_span).to be_root_span
          expect(server_queue_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_SERVER_QUEUE)
          expect(server_queue_span.span_type).to eq('proxy')
          expect(server_queue_span.service).to eq('web-server')
          expect(server_queue_span.resource).to eq('http_server.queue')
          expect(server_queue_span.get_tag('component')).to eq('rack')
          expect(server_queue_span.get_tag('operation')).to eq('queue')
          expect(server_queue_span.get_tag('peer.service')).to eq('web-server')
          expect(server_queue_span.status).to eq(0)
          expect(server_queue_span.get_tag('span.kind')).to eq('server')

          expect(rack_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST)
          expect(rack_span.span_type).to eq('web')
          expect(rack_span.service).to eq(tracer.default_service)
          expect(rack_span.resource).to eq('GET 200')
          expect(rack_span.get_tag('http.method')).to eq('GET')
          expect(rack_span.get_tag('http.status_code')).to eq('200')
          expect(rack_span.status).to eq(0)
          expect(rack_span.get_tag('component')).to eq('rack')
          expect(rack_span.get_tag('operation')).to eq('request')
          expect(rack_span.get_tag('span.kind')).to eq('server')
        end
      end

      describe 'when request queueing excludes the request time' do
        let(:rack_options) { { request_queuing: :exclude_request } }

        it 'creates web_server_span and rack span' do
          get 'request_queuing_enabled',
            nil,
            { Datadog::Tracing::Contrib::Rack::QueueTime::REQUEST_START => "t=#{Time.now.to_f}" }

          expect(trace.resource).to eq('GET 200')

          expect(spans).to have(3).items

          server_request_span = spans[1]
          server_queue_span = spans[0]
          rack_span = spans[2]

          expect(server_request_span).to be_root_span
          expect(server_request_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_PROXY_REQUEST)
          expect(server_request_span.span_type).to eq('proxy')
          expect(server_request_span.service).to eq('web-server')
          expect(server_request_span.resource).to eq('http.proxy.request')
          expect(server_request_span.get_tag('component')).to eq('http_proxy')
          expect(server_request_span.get_tag('operation')).to eq('request')
          expect(server_request_span.get_tag('peer.service')).to eq('web-server')
          expect(server_request_span.status).to eq(0)
          expect(server_request_span.get_tag('span.kind')).to eq('proxy')

          expect(server_queue_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_PROXY_QUEUE)
          expect(server_queue_span.span_type).to eq('proxy')
          expect(server_queue_span.service).to eq('web-server')
          expect(server_queue_span.resource).to eq('http.proxy.queue')
          expect(server_queue_span.get_tag('component')).to eq('http_proxy')
          expect(server_queue_span.get_tag('operation')).to eq('queue')
          expect(server_queue_span.get_tag('peer.service')).to eq('web-server')
          expect(server_queue_span.status).to eq(0)
          expect(server_queue_span.get_tag('span.kind')).to eq('proxy')
          expect(server_queue_span).to be_measured

          expect(rack_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST)
          expect(rack_span.span_type).to eq('web')
          expect(rack_span.service).to eq(tracer.default_service)
          expect(rack_span.resource).to eq('GET 200')
          expect(rack_span.get_tag('http.method')).to eq('GET')
          expect(rack_span.get_tag('http.status_code')).to eq('200')
          expect(rack_span.status).to eq(0)
          expect(rack_span.get_tag('component')).to eq('rack')
          expect(rack_span.get_tag('operation')).to eq('request')
          expect(rack_span.get_tag('span.kind')).to eq('server')
        end
      end
    end

    context 'with a route that has a client error' do
      let(:routes) do
        proc do
          map '/failure/' do
            run(proc { |_env| [400, { 'Content-Type' => 'text/html' }, ['KO']] })
          end
        end
      end

      before do
        expect(response.status).to eq(400)
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get '/failure/' }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq(Datadog.configuration.service)
          expect(span.resource).to eq('GET 400')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('400')
          expect(span.get_tag('http.url')).to eq('/failure/')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.status).to eq(0)
          expect(span).to be_root_span
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq('rack')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('request')
          expect(span.get_tag('span.kind'))
            .to eq('server')
        end
      end
    end

    context 'with a route that has a server error' do
      let(:routes) do
        proc do
          map '/server_error/' do
            run(proc { |_env| [500, { 'Content-Type' => 'text/html' }, ['KO']] })
          end
        end
      end

      before do
        is_expected.to be_server_error
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get '/server_error/' }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq(Datadog.configuration.service)
          expect(span.resource).to eq('GET 500')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('500')
          expect(span.get_tag('http.url')).to eq('/server_error/')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.get_tag('error.stack')).to be nil
          expect(span.status).to eq(1)
          expect(span).to be_root_span
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq('rack')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('request')
          expect(span.get_tag('span.kind'))
            .to eq('server')
        end
      end
    end

    context 'with a route that raises an exception' do
      context 'that is well known' do
        let(:routes) do
          proc do
            map '/exception/' do
              run(proc { |_env| raise StandardError, 'Unable to process the request' })
            end
          end
        end

        before do
          expect { response }.to raise_error(StandardError)
          expect(spans).to have(1).items
        end

        describe 'GET request' do
          subject(:response) { get '/exception/' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq(Datadog.configuration.service)
            expect(span.resource).to eq('GET')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to be nil
            expect(span.get_tag('http.url')).to eq('/exception/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.get_tag('error.type')).to eq('StandardError')
            expect(span.get_tag('error.message')).to eq('Unable to process the request')
            expect(span.get_tag('error.stack')).to_not be nil
            expect(span.status).to eq(1)
            expect(span).to be_root_span
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq('rack')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('request')
            expect(span.get_tag('span.kind'))
              .to eq('server')
          end
        end
      end

      context 'that is not a standard error' do
        let(:routes) do
          proc do
            map '/exception/' do
              run(proc { |_env| raise NoMemoryError, 'Non-standard error' })
            end
          end
        end

        before do
          expect { response }.to raise_error(NoMemoryError)
          expect(spans).to have(1).items
        end

        describe 'GET request' do
          subject(:response) { get '/exception/' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq(Datadog.configuration.service)
            expect(span.resource).to eq('GET')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to be nil
            expect(span.get_tag('http.url')).to eq('/exception/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.get_tag('error.type')).to eq('NoMemoryError')
            expect(span.get_tag('error.message')).to eq('Non-standard error')
            expect(span.get_tag('error.stack')).to_not be nil
            expect(span.status).to eq(1)
            expect(span).to be_root_span
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq('rack')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('request')
            expect(span.get_tag('span.kind'))
              .to eq('server')
          end
        end
      end
    end

    context 'with a route with a nested application' do
      context 'that is OK' do
        let(:routes) do
          proc do
            map '/app/' do
              run(
                proc do |env|
                  # This should be considered a web framework that can alter
                  # the request span after routing / controller processing
                  request_span = env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
                  request_span.resource = 'GET /app/'
                  request_span.set_tag('http.method', 'GET_V2')
                  request_span.set_tag('http.status_code', 201)
                  request_span.set_tag('http.url', '/app/static/')

                  [200, { 'Content-Type' => 'text/html' }, ['OK']]
                end
              )
            end
          end
        end

        before do
          is_expected.to be_ok
          expect(spans).to have(1).items
        end

        describe 'GET request' do
          subject(:response) { get route }

          context 'without parameters' do
            let(:route) { '/app/posts/100' }

            it do
              expect(trace.resource).to eq('GET /app/')

              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq(Datadog.configuration.service)
              expect(span.resource).to eq('GET /app/')
              expect(span.get_tag('http.method')).to eq('GET_V2')
              expect(span.get_tag('http.status_code')).to eq('201')
              expect(span.get_tag('http.url')).to eq('/app/static/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.status).to eq(0)
              expect(span).to be_root_span
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
                .to eq('rack')
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
                .to eq('request')
              expect(span.get_tag('span.kind'))
                .to eq('server')
            end
          end
        end
      end

      context 'when `request_queuing` enabled with `:include_request` and trace resource overwritten by nested app' do
        let(:rack_options) { { request_queuing: :include_request } }
        let(:routes) do
          proc do
            map '/resource_override' do
              run(
                proc do |_env|
                  Datadog::Tracing.trace('nested_app', resource: 'UserController#show') do |span_op, trace_op|
                    trace_op.resource = span_op.resource

                    [200, { 'Content-Type' => 'text/html' }, ['OK']]
                  end
                end
              )
            end
          end
        end

        it 'creates a web_server span and rack span with resource overriden' do
          get '/resource_override',
            nil,
            { Datadog::Tracing::Contrib::Rack::QueueTime::REQUEST_START => "t=#{Time.now.to_f}" }

          expect(trace.resource).to eq('UserController#show')

          expect(spans).to have(3).items

          server_queue_span = spans[0]
          rack_span = spans[2]
          nested_app_span = spans[1]

          expect(server_queue_span).to be_root_span
          expect(server_queue_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_SERVER_QUEUE)
          expect(server_queue_span.span_type).to eq('proxy')
          expect(server_queue_span.service).to eq('web-server')
          expect(server_queue_span.resource).to eq('http_server.queue')
          expect(server_queue_span.get_tag('component')).to eq('rack')
          expect(server_queue_span.get_tag('operation')).to eq('queue')
          expect(server_queue_span.get_tag('peer.service')).to eq('web-server')
          expect(server_queue_span.status).to eq(0)
          expect(server_queue_span.get_tag('span.kind')).to eq('server')

          expect(rack_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST)
          expect(rack_span.span_type).to eq('web')
          expect(rack_span.service).to eq(tracer.default_service)
          expect(rack_span.resource).to eq('UserController#show')
          expect(rack_span.get_tag('http.method')).to eq('GET')
          expect(rack_span.get_tag('http.status_code')).to eq('200')
          expect(rack_span.status).to eq(0)
          expect(rack_span.get_tag('component')).to eq('rack')
          expect(rack_span.get_tag('operation')).to eq('request')
          expect(rack_span.get_tag('span.kind')).to eq('server')

          expect(nested_app_span.name).to eq('nested_app')
          expect(nested_app_span.resource).to eq('UserController#show')
        end
      end

      context 'when `request_queuing` enabled with `:exclude_request` and trace resource overwritten by nested app' do
        let(:rack_options) { { request_queuing: :exclude_request } }
        let(:routes) do
          proc do
            map '/resource_override' do
              run(
                proc do |_env|
                  Datadog::Tracing.trace('nested_app', resource: 'UserController#show') do |span_op, trace_op|
                    trace_op.resource = span_op.resource

                    [200, { 'Content-Type' => 'text/html' }, ['OK']]
                  end
                end
              )
            end
          end
        end

        it 'creates 2 web_server spans and rack span with resource overriden' do
          get '/resource_override',
            nil,
            { Datadog::Tracing::Contrib::Rack::QueueTime::REQUEST_START => "t=#{Time.now.to_f}" }

          expect(trace.resource).to eq('UserController#show')

          expect(spans).to have(4).items

          server_request_span = spans[1]
          server_queue_span = spans[0]
          rack_span = spans[3]
          nested_app_span = spans[2]

          expect(server_request_span).to be_root_span
          expect(server_request_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_PROXY_REQUEST)
          expect(server_request_span.span_type).to eq('proxy')
          expect(server_request_span.service).to eq('web-server')
          expect(server_request_span.resource).to eq('http.proxy.request')
          expect(server_request_span.get_tag('component')).to eq('http_proxy')
          expect(server_request_span.get_tag('operation')).to eq('request')
          expect(server_request_span.get_tag('peer.service')).to eq('web-server')
          expect(server_request_span.status).to eq(0)
          expect(server_request_span.get_tag('span.kind')).to eq('proxy')

          expect(server_queue_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_PROXY_QUEUE)
          expect(server_queue_span.span_type).to eq('proxy')
          expect(server_queue_span.service).to eq('web-server')
          expect(server_queue_span.resource).to eq('http.proxy.queue')
          expect(server_queue_span.get_tag('component')).to eq('http_proxy')
          expect(server_queue_span.get_tag('operation')).to eq('queue')
          expect(server_queue_span.get_tag('peer.service')).to eq('web-server')
          expect(server_queue_span.status).to eq(0)
          expect(server_queue_span.get_tag('span.kind')).to eq('proxy')
          expect(server_queue_span).to be_measured

          expect(rack_span.name).to eq(Datadog::Tracing::Contrib::Rack::Ext::SPAN_REQUEST)
          expect(rack_span.span_type).to eq('web')
          expect(rack_span.service).to eq(tracer.default_service)
          expect(rack_span.resource).to eq('UserController#show')
          expect(rack_span.get_tag('http.method')).to eq('GET')
          expect(rack_span.get_tag('http.status_code')).to eq('200')
          expect(rack_span.status).to eq(0)
          expect(rack_span.get_tag('component')).to eq('rack')
          expect(rack_span.get_tag('operation')).to eq('request')
          expect(rack_span.get_tag('span.kind')).to eq('server')

          expect(nested_app_span.name).to eq('nested_app')
          expect(nested_app_span.resource).to eq('UserController#show')
        end
      end

      context 'that raises a server error' do
        before do
          is_expected.to be_server_error
          expect(spans).to have(1).items
        end

        context 'while setting status' do
          let(:routes) do
            proc do
              map '/app/500/' do
                run(
                  proc do |env|
                    # this should be considered a web framework that can alter
                    # the request span after routing / controller processing
                    request_span = env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
                    request_span.status = 1
                    request_span.set_tag('error.stack', 'Handled exception')

                    [500, { 'Content-Type' => 'text/html' }, ['OK']]
                  end
                )
              end
            end
          end

          describe 'GET request' do
            subject(:response) { get '/app/500/' }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq(Datadog.configuration.service)
              expect(span.resource).to eq('GET 500')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq('500')
              expect(span.get_tag('http.url')).to eq('/app/500/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.get_tag('error.stack')).to eq('Handled exception')
              expect(span.status).to eq(1)
              expect(span).to be_root_span
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
                .to eq('rack')
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
                .to eq('request')
              expect(span.get_tag('span.kind'))
                .to eq('server')
            end
          end
        end

        context 'without setting status' do
          let(:routes) do
            proc do
              map '/app/500/' do
                run(
                  proc do |env|
                    # this should be considered a web framework that can alter
                    # the request span after routing / controller processing
                    request_span = env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
                    request_span.set_tag('error.stack', 'Handled exception')

                    [500, { 'Content-Type' => 'text/html' }, ['OK']]
                  end
                )
              end
            end
          end

          describe 'GET request' do
            subject(:response) { get '/app/500/' }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq(Datadog.configuration.service)
              expect(span.resource).to eq('GET 500')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq('500')
              expect(span.get_tag('http.url')).to eq('/app/500/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.get_tag('error.stack')).to eq('Handled exception')
              expect(span.status).to eq(1)
              expect(span).to be_root_span
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
                .to eq('rack')
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
                .to eq('request')
              expect(span.get_tag('span.kind'))
                .to eq('server')
            end
          end
        end
      end
    end

    context 'with a route that leaks span context' do
      let(:routes) do
        app_tracer = tracer

        proc do
          map '/leak/' do
            handler = proc do
              app_tracer.trace('leaky-span-1')
              app_tracer.trace('leaky-span-2')
              app_tracer.trace('leaky-span-3')

              [200, { 'Content-Type' => 'text/html' }, ['OK']]
            end

            run(handler)
          end

          map '/success/' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
          end
        end
      end

      describe 'subsequent GET requests' do
        subject(:responses) { [(get '/leak'), (get '/success')] }

        before do
          responses.each { |response| expect(response).to be_ok }
          expect(spans).to have(2).items
        end

        it do
          # Ensure the context is properly cleaned between requests.
          expect(tracer.active_trace).to be nil
          expect(spans).to have(2).items
        end
      end
    end

    context 'with a route that sets some headers' do
      let(:routes) do
        proc do
          map '/headers/' do
            run(
              proc do |_env|
                response_headers = {
                  'Content-Type' => 'text/html',
                  'Cache-Control' => 'max-age=3600',
                  'ETag' => '"737060cd8c284d8af7ad3082f209582d"',
                  'Expires' => 'Thu, 01 Dec 1994 16:00:00 GMT',
                  'Last-Modified' => 'Tue, 15 Nov 1994 12:45:26 GMT',
                  'X-Request-ID' => 'f058ebd6-02f7-4d3f-942e-904344e8cde5',
                  'X-Fake-Response' => 'Don\'t tag me.'
                }
                [200, response_headers, ['OK']]
              end
            )
          end
        end
      end

      context 'when configured to tag headers' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :rack,
              headers: {
                request: [
                  'Cache-Control'
                ],
                response: [
                  'Content-Type',
                  'Cache-Control',
                  'Content-Type',
                  'ETag',
                  'Expires',
                  'Last-Modified',
                  # This lowercase 'Id' header doesn't match.
                  # Ensure middleware allows for case-insensitive matching.
                  'X-Request-Id'
                ]
              }
          end
        end

        after do
          # Reset to default headers
          Datadog.configure do |c|
            c.tracing.instrument :rack, headers: {}
          end
        end

        describe 'GET request' do
          context 'that does not sent user agent' do
            subject(:response) { get '/headers/', {}, headers }

            let(:headers) do
              {}
            end

            before do
              is_expected.to be_ok
              expect(spans).to have(1).items
            end

            it_behaves_like 'a rack GET 200 span'

            it do
              expect(span.get_tag('http.useragent')).to be nil
              expect(span.get_tag('http.request.headers.user-agent')).to be nil
            end
          end

          context 'that sends user agent' do
            subject(:response) { get '/headers/', {}, headers }

            let(:headers) do
              {
                'HTTP_USER_AGENT' => 'SuperUserAgent',
              }
            end

            before do
              is_expected.to be_ok
              expect(spans).to have(1).items
            end

            it_behaves_like 'a rack GET 200 span'

            it do
              expect(span.get_tag('http.useragent')).to eq('SuperUserAgent')
              expect(span.get_tag('http.request.headers.user-agent')).to be nil
            end
          end

          context 'that sends headers' do
            subject(:response) { get '/headers/', {}, headers }

            let(:headers) do
              {
                'HTTP_CACHE_CONTROL' => 'no-cache',
                'HTTP_X_REQUEST_ID' => SecureRandom.uuid,
                'HTTP_X_FAKE_REQUEST' => 'Don\'t tag me.'
              }
            end

            before do
              is_expected.to be_ok
              expect(spans).to have(1).items
            end

            it_behaves_like 'a rack GET 200 span'

            it do
              expect(span.get_tag('http.url')).to eq('/headers/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span).to be_root_span

              # Request headers
              expect(span.get_tag('http.request.headers.cache-control')).to eq('no-cache')
              # Make sure non-whitelisted headers don't become tags.
              expect(span.get_tag('http.request.headers.x-request-id')).to be nil
              expect(span.get_tag('http.request.headers.x-fake-request')).to be nil

              # Response headers
              expect(span.get_tag('http.response.headers.content-type')).to eq('text/html')
              expect(span.get_tag('http.response.headers.cache-control')).to eq('max-age=3600')
              expect(span.get_tag('http.response.headers.etag')).to eq('"737060cd8c284d8af7ad3082f209582d"')
              expect(span.get_tag('http.response.headers.last-modified')).to eq('Tue, 15 Nov 1994 12:45:26 GMT')
              expect(span.get_tag('http.response.headers.x-request-id')).to eq('f058ebd6-02f7-4d3f-942e-904344e8cde5')
              # Make sure non-whitelisted headers don't become tags.
              expect(span.get_tag('http.request.headers.x-fake-response')).to be nil
            end
          end
        end
      end
    end

    context 'with a route that mutates request method' do
      let(:routes) do
        proc do
          map '/change_request_method' do
            run(
              proc do |env|
                env['REQUEST_METHOD'] = 'GET'
                [200, { 'Content-Type' => 'text/html' }, ['OK']]
              end
            )
          end
        end
      end

      it do
        post '/change_request_method'

        expect(span).to be_root_span
        expect(span.name).to eq('rack.request')
        expect(span.span_type).to eq('web')
        expect(span.service).to eq(tracer.default_service)
        expect(span.resource).to eq('POST 200')
        expect(span.get_tag('http.method')).to eq('POST')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.status).to eq(0)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
        expect(span.get_tag('span.kind')).to eq('server')
      end
    end
  end

  context 'for a nested instrumentation' do
    let(:another) do
      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware

        map '/success' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
        end
      end.to_app
    end

    let(:app) do
      nested_app = another

      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware

        map '/nested' do
          use Datadog::Tracing::Contrib::Rack::TraceMiddleware

          run nested_app
        end
      end.to_app
    end

    subject(:response) { get 'nested/success' }

    before do
      is_expected.to be_ok
      expect(spans).to have(1).items
    end

    it_behaves_like 'a rack GET 200 span'
  end
end
