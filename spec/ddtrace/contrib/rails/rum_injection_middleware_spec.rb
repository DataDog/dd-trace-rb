require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails Rack Rum Injection middleware' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    {
      '/' => 'rum_test#index',
      '/cached_page' => 'rum_test_cached_page#index',
      '/rum_manual_injection' => 'rum_test_manual_injection#index',
      '/rum_manual_injection_no_env' => 'rum_test_manual_injection_no_env#index'
    }
  end

  let(:controllers) do
    [
      controller,
      cached_page_controller,
      rum_test_manual_injection_controller,
      rum_test_manual_injection_no_env_controller
    ]
  end

  let(:controller) do
    stub_const('RumTestController', Class.new(ActionController::Base) do
      def index
        response.headers['Cache-Control'] = 'max-age=0'
        render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>'
      end
    end)
  end

  let(:cached_page_controller) do
    stub_const('RumTestCachedPageController', Class.new(ActionController::Base) do
      def index
        response.headers['Cache-Control'] = 'max-age=60'
        render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>'
      end
    end)
  end

  let(:cached_page_controller) do
    stub_const('RumTestCachedPageController', Class.new(ActionController::Base) do
      def index
        response.headers['Cache-Control'] = 'max-age=60'
        render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>'
      end
    end)
  end

  let(:rum_test_manual_injection_controller) do
    stub_const('RumTestManualInjectionController', Class.new(ActionController::Base) do
      def index
        response.headers['Cache-Control'] = 'max-age=0s'
        render inline: "<html> <head> #{::Datadog::Contrib::Rack::RumInjection.inject_rum_data(request.env)}</head>\
         <body> <div> Hello from index </div> </body> </html>"
      end
    end)
  end

  let(:rum_test_manual_injection_no_env_controller) do
    stub_const('RumTestManualInjectionNoEnvController', Class.new(ActionController::Base) do
      def index
        response.headers['Cache-Control'] = 'max-age=0s'
        render inline: "<html> <head> #{::Datadog::Contrib::Rack::RumInjection.inject_rum_data}</head>\
         <body> <div> Hello from index </div> </body> </html>"
      end
    end)
  end

  before do
    Datadog.configuration[:rack].reset_options!
    Datadog.configuration[:rails].reset_options!

    Datadog.configure do |c|
      c.use :rack, rum_injection_enabled: true
      c.use :rails
    end
  end

  after do
    Datadog.configuration[:rack].reset_options!
    Datadog.configuration[:rails].reset_options!
  end

  context 'with RumInjection middleware' do
    context 'with no caching from controller' do
      subject(:response) { get '/' }

      it 'should inject trace_id into html response' do
        expect(response.body).to include(spans[0].trace_id.to_s)
      end
    end

    context 'with caching from controller' do
      subject(:response) { get '/cached_page' }

      it 'should not inject trace_id into html response' do
        expect(response.body).to_not include(spans[0].trace_id.to_s)
      end
    end

    context 'with RUM manual injection enabled' do
      context 'and with rack env passed in' do
        subject(:response) { get '/rum_manual_injection' }

        it 'injects the html meta tag containing trace_id' do
          expect(response.body).to include(spans[0].trace_id.to_s)
          expect(response.body).to include('dd-trace-id')
        end

        it 'injects the html meta tag containing ms precision trace-time' do
          expect(response.body).to match(/.*content="\d{13}".*/)
          expect(response.body).to include('name="dd-trace-time"')
        end

        it 'disables HTML comments from automatic injection' do
          expect(response.body).to_not include('DATADOG')
        end
      end

      context 'and with rack env not passed in' do
        subject(:response) { get '/rum_manual_injection_no_env' }

        it 'injects the html meta tag containing trace_id' do
          expect(response.body).to include(spans[0].trace_id.to_s)
          expect(response.body).to include('dd-trace-id')
        end

        it 'injects the html meta tag containing ms precision trace-time' do
          expect(response.body).to match(/.*content="\d{13}".*/)
          expect(response.body).to include('name="dd-trace-time"')
        end

        it 'does not disable HTML Comments from automatic injection' do
          expect(response.body).to include('DATADOG')
        end
      end
    end

    if Rails.version >= '3.2'
      context 'with stream from controller' do
        # i think this is when ActionControlller::Streaming was introduced
        # ActionController::Live was in >=5

        let(:streaming_page_controller) do
          stub_const('RumTestStreamingPageController', Class.new(ActionController::Base) do
            def index
              response.headers['Cache-Control'] = 'max-age=0'
              render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>', stream: true
            end
          end)
        end

        let(:controllers) { [controller, cached_page_controller, streaming_page_controller] }
        let(:routes) do
          {
            '/' => 'rum_test#index',
            '/cached_page' => 'rum_test_cached_page#index',
            '/streaming_page' => 'rum_test_streaming_page#index'
          }
        end

        subject(:response) { get '/streaming_page' }

        it 'should not inject trace_id into streamed html response regardless of caching behavior' do
          expect(response.body).to_not include(spans[0].trace_id.to_s)
        end
      end
    end
  end
end
