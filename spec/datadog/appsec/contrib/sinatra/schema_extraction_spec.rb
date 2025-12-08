# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'sinatra/base'
require 'sinatra/json'
require 'datadog/tracing'
require 'datadog/appsec'

# TODO: JRuby 10.0 - Remove this skip after investigation.
RSpec.describe 'Schema extraction for API security in Sinatra', skip: PlatformHelpers.jruby_100? do
  include Rack::Test::Methods

  before do
    Datadog.configure do |config|
      config.tracing.enabled = true
      config.tracing.instrument :sinatra

      config.apm.tracing.enabled = true
      config.remote.enabled = false

      config.appsec.enabled = true
      config.appsec.instrument :sinatra
      config.appsec.api_security.sample_delay = 0
      config.appsec.api_security.enabled = true
      config.appsec.ruleset = {
        rules: [
          {
            id: 'rasp-003-001',
            name: 'SQL Injection',
            tags: {
              type: 'sql_injection',
              category: 'exploit',
              module: 'rasp'
            },
            conditions: [
              {
                operator: 'sqli_detector',
                parameters: {
                  resource: [{address: 'server.db.statement'}],
                  params: [{address: 'server.request.query'}],
                  db_type: [{address: 'server.db.system'}]
                }
              }
            ],
            on_match: ['block']
          }
        ],
        processors: [
          {
            id: "extract-content",
            generator: "extract_schema",
            conditions: [
              {
                operator: "equals",
                parameters: {
                  inputs: [
                    {
                      address: "waf.context.processor",
                      key_path: ["extract-schema"]
                    }
                  ],
                  type: "boolean",
                  value: true
                }
              }
            ],
            parameters: {
              mappings: [
                {
                  inputs: [{address: "server.request.body"}],
                  output: "_dd.appsec.s.req.body"
                },
                {
                  inputs: [{address: "server.request.cookies"}],
                  output: "_dd.appsec.s.req.cookies"
                },
                {
                  inputs: [{address: "server.request.query"}],
                  output: "_dd.appsec.s.req.query"
                },
                {
                  inputs: [{address: "server.request.path_params"}],
                  output: "_dd.appsec.s.req.params"
                },
                {
                  inputs: [{address: "server.response.body"}],
                  output: "_dd.appsec.s.res.body"
                }
              ]
            },
            evaluate: false,
            output: true
          },
          {
            id: "extract-headers",
            generator: "extract_schema",
            conditions: [
              {
                operator: "equals",
                parameters: {
                  inputs: [
                    {
                      address: "waf.context.processor",
                      key_path: ["extract-schema"]
                    }
                  ],
                  type: "boolean",
                  value: true
                }
              }
            ],
            parameters: {
              mappings: [
                {
                  inputs: [{address: "server.request.headers.no_cookies"}],
                  output: "_dd.appsec.s.req.headers"
                },
                {
                  inputs: [{address: "server.response.headers.no_cookies"}],
                  output: "_dd.appsec.s.res.headers"
                }
              ]
            },
            evaluate: false,
            output: true
          },
        ]
      }
    end

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?).and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

  let(:app) do
    klass = Class.new(Sinatra::Base) do
      set :show_exceptions, false
      set :raise_errors, true

      get '/product' do
        json(id: 1, name: 'Widget', price: 29.99)
      end
    end

    klass.new
  end

  subject(:response) { last_response }

  context 'when API security is enabled' do
    before { get('/product') }

    it 'extracts request and response body schema' do
      expect(response).to be_ok
      expect(http_service_entry_span.tags).to have_key('_dd.appsec.s.res.body')
    end
  end
end
