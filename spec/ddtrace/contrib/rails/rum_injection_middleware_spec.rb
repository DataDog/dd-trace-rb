require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails Rack Rum Injection middleware' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) { { '/' => 'rum_test#index', '/cached_page' => 'rum_test_cached_page#index' } }
  let(:controllers) { [controller, cached_page_controller] }

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
