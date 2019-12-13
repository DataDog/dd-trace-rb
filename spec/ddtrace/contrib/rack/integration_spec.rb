require 'spec_helper'
require 'rack/test'
require 'securerandom'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  let(:tracer) { get_test_tracer }
  let(:rack_options) { { tracer: tracer } }

  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before(:each) do
    Datadog.configure do |c|
      c.use :rack, rack_options
    end
  end

  context 'for an application' do
    let(:app) do
      app_routes = routes

      Rack::Builder.new do
        use Datadog::Contrib::Rack::TraceMiddleware
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

      before(:each) do
        is_expected.to be_not_found
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get '/not/exists/' }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq('rack')
          expect(span.resource).to eq('GET 404')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq(404)
          expect(span.get_tag('http.url')).to eq('/not/exists/')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.status).to eq(0)
          expect(span.parent).to be nil
        end
      end
    end

    context 'with a basic route' do
      let(:routes) do
        proc do
          map '/success/' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
          end
        end
      end

      before(:each) do
        is_expected.to be_ok
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get route }

        context 'without parameters' do
          let(:route) { '/success/' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq('rack')
            expect(span.resource).to eq('GET 200')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to eq(200)
            expect(span.get_tag('http.url')).to eq('/success/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.status).to eq(0)
            expect(span.parent).to be nil
          end
        end

        context 'with query string parameters' do
          let(:route) { '/success?foo=bar' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq('rack')
            expect(span.resource).to eq('GET 200')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to eq(200)
            # Since REQUEST_URI isn't available in Rack::Test by default (comes from WEBrick/Puma)
            # it reverts to PATH_INFO, which doesn't have query string parameters.
            expect(span.get_tag('http.url')).to eq('/success')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.status).to eq(0)
            expect(span.parent).to be nil
          end
        end

        context 'with REQUEST_URI' do
          subject(:response) { get '/success?foo=bar', {}, 'REQUEST_URI' => '/success?foo=bar' }

          context 'and default quantization' do
            let(:rack_options) { super().merge(quantize: {}) }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq('rack')
              expect(span.resource).to eq('GET 200')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq(200)
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # However, that query string will be quantized.
              expect(span.get_tag('http.url')).to eq('/success?foo')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.status).to eq(0)
              expect(span.parent).to be nil
            end
          end

          context 'and quantization activated for the query' do
            let(:rack_options) { super().merge(quantize: { query: { show: ['foo'] } }) }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq('rack')
              expect(span.resource).to eq('GET 200')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq(200)
              # Since REQUEST_URI is set (usually provided by WEBrick/Puma)
              # it uses REQUEST_URI, which has query string parameters.
              # The query string will not be quantized, per the option.
              expect(span.get_tag('http.url')).to eq('/success?foo=bar')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.status).to eq(0)
              expect(span.parent).to be nil
            end
          end
        end

        context 'with sub-route' do
          let(:route) { '/success/100' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq('rack')
            expect(span.resource).to eq('GET 200')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to eq(200)
            expect(span.get_tag('http.url')).to eq('/success/100')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.status).to eq(0)
            expect(span.parent).to be nil
          end
        end

        context 'when configured with a custom service name' do
          let(:route) { '/success/' }
          let(:rack_options) { super().merge(service_name: service_name) }
          let(:service_name) { 'custom-rack' }

          after(:each) do
            Datadog.configure do |c|
              c.use :rack, service_name: Datadog::Contrib::Rack::Ext::SERVICE_NAME
            end
          end

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq('custom-rack')
            expect(span.resource).to eq('GET 200')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to eq(200)
            expect(span.get_tag('http.url')).to eq('/success/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.status).to eq(0)
            expect(span.parent).to be nil
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
            expect(span.service).to eq('rack')
            expect(span.resource).to eq('POST 200')
            expect(span.get_tag('http.method')).to eq('POST')
            expect(span.get_tag('http.status_code')).to eq(200)
            expect(span.get_tag('http.url')).to eq('/success/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.status).to eq(0)
            expect(span.parent).to be nil
          end
        end
      end
    end

    context 'with a route that has a client error' do
      let(:routes) do
        proc do
          map '/failure/' do
            run(proc { |_env| [400, { 'Content-Type' => 'text/html' }, 'KO'] })
          end
        end
      end

      before(:each) do
        expect(response.status).to eq(400)
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get '/failure/' }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq('rack')
          expect(span.resource).to eq('GET 400')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq(400)
          expect(span.get_tag('http.url')).to eq('/failure/')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.status).to eq(0)
          expect(span.parent).to be nil
        end
      end
    end

    context 'with a route that has a server error' do
      let(:routes) do
        proc do
          map '/server_error/' do
            run(proc { |_env| [500, { 'Content-Type' => 'text/html' }, 'KO'] })
          end
        end
      end

      before(:each) do
        is_expected.to be_server_error
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get '/server_error/' }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq('rack')
          expect(span.resource).to eq('GET 500')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq(500)
          expect(span.get_tag('http.url')).to eq('/server_error/')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.get_tag('error.stack')).to be nil
          expect(span.status).to eq(1)
          expect(span.parent).to be nil
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

        before(:each) do
          expect { response }.to raise_error(StandardError)
          expect(spans).to have(1).items
        end

        describe 'GET request' do
          subject(:response) { get '/exception/' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq('rack')
            expect(span.resource).to eq('GET')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to be nil
            expect(span.get_tag('http.url')).to eq('/exception/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.get_tag('error.type')).to eq('StandardError')
            expect(span.get_tag('error.msg')).to eq('Unable to process the request')
            expect(span.get_tag('error.stack')).to_not be nil
            expect(span.status).to eq(1)
            expect(span.parent).to be nil
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

        before(:each) do
          expect { response }.to raise_error(NoMemoryError)
          expect(spans).to have(1).items
        end

        describe 'GET request' do
          subject(:response) { get '/exception/' }

          it do
            expect(span.name).to eq('rack.request')
            expect(span.span_type).to eq('web')
            expect(span.service).to eq('rack')
            expect(span.resource).to eq('GET')
            expect(span.get_tag('http.method')).to eq('GET')
            expect(span.get_tag('http.status_code')).to be nil
            expect(span.get_tag('http.url')).to eq('/exception/')
            expect(span.get_tag('http.base_url')).to eq('http://example.org')
            expect(span.get_tag('error.type')).to eq('NoMemoryError')
            expect(span.get_tag('error.msg')).to eq('Non-standard error')
            expect(span.get_tag('error.stack')).to_not be nil
            expect(span.status).to eq(1)
            expect(span.parent).to be nil
          end
        end
      end
    end

    context 'with a route with a nested application' do
      context 'that is OK' do
        let(:routes) do
          proc do
            map '/app/' do
              run(proc do |env|
                # This should be considered a web framework that can alter
                # the request span after routing / controller processing
                request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
                request_span.resource = 'GET /app/'
                request_span.set_tag('http.method', 'GET_V2')
                request_span.set_tag('http.status_code', 201)
                request_span.set_tag('http.url', '/app/static/')

                [200, { 'Content-Type' => 'text/html' }, 'OK']
              end)
            end
          end
        end

        before(:each) do
          is_expected.to be_ok
          expect(spans).to have(1).items
        end

        describe 'GET request' do
          subject(:response) { get route }

          context 'without parameters' do
            let(:route) { '/app/posts/100' }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq('rack')
              expect(span.resource).to eq('GET /app/')
              expect(span.get_tag('http.method')).to eq('GET_V2')
              expect(span.get_tag('http.status_code')).to eq(201)
              expect(span.get_tag('http.url')).to eq('/app/static/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.status).to eq(0)
              expect(span.parent).to be nil
            end
          end
        end
      end

      context 'that raises a server error' do
        before(:each) do
          is_expected.to be_server_error
          expect(spans).to have(1).items
        end

        context 'while setting status' do
          let(:routes) do
            proc do
              map '/app/500/' do
                run(proc do |env|
                  # this should be considered a web framework that can alter
                  # the request span after routing / controller processing
                  request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
                  request_span.status = 1
                  request_span.set_tag('error.stack', 'Handled exception')

                  [500, { 'Content-Type' => 'text/html' }, 'OK']
                end)
              end
            end
          end

          describe 'GET request' do
            subject(:response) { get '/app/500/' }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq('rack')
              expect(span.resource).to eq('GET 500')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq(500)
              expect(span.get_tag('http.url')).to eq('/app/500/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.get_tag('error.stack')).to eq('Handled exception')
              expect(span.status).to eq(1)
              expect(span.parent).to be nil
            end
          end
        end

        context 'without setting status' do
          let(:routes) do
            proc do
              map '/app/500/' do
                run(proc do |env|
                  # this should be considered a web framework that can alter
                  # the request span after routing / controller processing
                  request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
                  request_span.set_tag('error.stack', 'Handled exception')

                  [500, { 'Content-Type' => 'text/html' }, 'OK']
                end)
              end
            end
          end

          describe 'GET request' do
            subject(:response) { get '/app/500/' }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq('rack')
              expect(span.resource).to eq('GET 500')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq(500)
              expect(span.get_tag('http.url')).to eq('/app/500/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.get_tag('error.stack')).to eq('Handled exception')
              expect(span.status).to eq(1)
              expect(span.parent).to be nil
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

              [200, { 'Content-Type' => 'text/html' }, 'OK']
            end

            run(handler)
          end

          map '/success/' do
            run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
          end
        end
      end

      describe 'subsequent GET requests' do
        subject(:responses) { [(get '/leak'), (get '/success')] }

        before(:each) do
          responses.each { |response| expect(response).to be_ok }
          expect(spans).to have(1).items
        end

        it do
          # Ensure the context is properly cleaned between requests.
          expect(tracer.provider.context.instance_variable_get(:@trace).length).to eq(0)
          expect(spans).to have(1).items
        end
      end
    end

    context 'with a route that sets some headers' do
      let(:routes) do
        proc do
          map '/headers/' do
            run(proc do |_env|
              response_headers = {
                'Content-Type' => 'text/html',
                'Cache-Control' => 'max-age=3600',
                'ETag' => '"737060cd8c284d8af7ad3082f209582d"',
                'Expires' => 'Thu, 01 Dec 1994 16:00:00 GMT',
                'Last-Modified' => 'Tue, 15 Nov 1994 12:45:26 GMT',
                'X-Request-ID' => 'f058ebd6-02f7-4d3f-942e-904344e8cde5',
                'X-Fake-Response' => 'Don\'t tag me.'
              }
              [200, response_headers, 'OK']
            end)
          end
        end
      end

      context 'when configured to tag headers' do
        before(:each) do
          Datadog.configure do |c|
            c.use :rack, headers: {
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

        after(:each) do
          # Reset to default headers
          Datadog.configure do |c|
            c.use :rack, headers: {}
          end
        end

        describe 'GET request' do
          context 'that sends headers' do
            subject(:response) { get '/headers/', {}, headers }

            let(:headers) do
              {
                'HTTP_CACHE_CONTROL' => 'no-cache',
                'HTTP_X_REQUEST_ID' => SecureRandom.uuid,
                'HTTP_X_FAKE_REQUEST' => 'Don\'t tag me.'
              }
            end

            before(:each) do
              is_expected.to be_ok
              expect(spans).to have(1).items
            end

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.service).to eq('rack')
              expect(span.resource).to eq('GET 200')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq(200)
              expect(span.get_tag('http.url')).to eq('/headers/')
              expect(span.get_tag('http.base_url')).to eq('http://example.org')
              expect(span.status).to eq(0)
              expect(span.parent).to be nil

              # Request headers
              expect(span.get_tag('http.request.headers.cache_control')).to eq('no-cache')
              # Make sure non-whitelisted headers don't become tags.
              expect(span.get_tag('http.request.headers.x_request_id')).to be nil
              expect(span.get_tag('http.request.headers.x_fake_request')).to be nil

              # Response headers
              expect(span.get_tag('http.response.headers.content_type')).to eq('text/html')
              expect(span.get_tag('http.response.headers.cache_control')).to eq('max-age=3600')
              expect(span.get_tag('http.response.headers.etag')).to eq('"737060cd8c284d8af7ad3082f209582d"')
              expect(span.get_tag('http.response.headers.last_modified')).to eq('Tue, 15 Nov 1994 12:45:26 GMT')
              expect(span.get_tag('http.response.headers.x_request_id')).to eq('f058ebd6-02f7-4d3f-942e-904344e8cde5')
              # Make sure non-whitelisted headers don't become tags.
              expect(span.get_tag('http.request.headers.x_fake_response')).to be nil
            end
          end
        end
      end
    end
  end
end
