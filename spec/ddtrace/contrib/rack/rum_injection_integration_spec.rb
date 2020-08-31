require 'ddtrace/contrib/support/spec_helper'
require 'rack/test'
require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'
require 'ddtrace/contrib/rack/rum_injection'
require_relative 'support/rum_injection_integration_helper'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  # integration_test_response is an array of Objects which represent an HTTP response
  # that the RumInjectionMiddleware either should, or should not, inject trace-id into. Ex:
  # {
  #   "status": 200,
  #   "contentType": "text/html",
  #   "body": "<!DOCTYPE html><html><h1>hi!</h1></html>",
  #   "headers": {
  #     "Cache-Control": "max-age=3600",
  #     "Expires": "Thu Dec 30 1999 18:00:00 GMT-0600 (Central Standard Time)"
  #   },
  #   "shouldInject": false
  # }
  let(:integration_test_response) { RumInjectionHelpers.rum_injection_responses }
  let(:rack_options) { { rum_injection_enabled: true } }

  # somewhat hacky, pass the array index within the query string off the test request to the app
  # then look it up against the array stored as temp let.
  let(:app_routes) do
    integration_test_response_list = integration_test_response
    proc do
      map '/success/' do
        run(proc do |env|
          idx = env['QUERY_STRING'].to_i
          html_response = integration_test_response_list[idx]['body']
          content_type = integration_test_response_list[idx]['contentType']

          # for the specs an array of body responses indicates chunking
          transfer_encoding = integration_test_response_list[idx]['body'].is_a?(Array) ? 'chunked' : 'identity'
          response_headers = {
            'Content-Type' => content_type,
            'Transfer-Encoding' => transfer_encoding
          }.merge(integration_test_response_list[idx]['headers'])

          [
            integration_test_response_list[idx]['status'].to_i,
            response_headers,
            integration_test_response_list[idx]['body'].is_a?(Array) ? html_response : [html_response]
          ]
        end)
      end
    end
  end

  let(:app) do
    routes = app_routes
    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware
      use Datadog::Contrib::Rack::RumInjection
      instance_eval(&routes)
    end.to_app
  end

  before(:each) do
    # Undo the Rack middleware name patch
    Datadog.registry[:rack].patcher::PATCHERS.each do |patcher|
      remove_patch!(patcher)
    end

    Datadog.configure do |c|
      c.use :rack, rack_options
    end
  end

  after(:each) do
    Datadog.registry[:rack].reset_configuration!
  end

  context 'for an application' do
    context 'with a basic route' do
      RumInjectionHelpers.rum_injection_responses.each_with_index do |resp_details, idx|
        it 'should inject' do
          response = get "/success/?#{idx}"
          if resp_details['shouldInject']
            expect(response.body).to include(span.trace_id.to_s)
          else
            expect(response.body).to_not include(span.trace_id.to_s)
          end
        end
      end
    end
  end
end
