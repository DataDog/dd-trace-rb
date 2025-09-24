# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'rack/contrib'
require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Blocking with deny and pass list configuration' do
  include Rack::Test::Methods

  let(:jwt_ruleset) do
    {
      'version' => '2.2',
      'metadata' => {'rules_version' => '1.25.1'},
      'rules' => [
        {
          'id' => 'crs-942-100',
          'name' => 'SQL Injection Attack Detected via libinjection',
          'tags' => {'type' => 'sql_injection', 'category' => 'attack_attempt'},
          'conditions' => [
            {
              'parameters' => {'inputs' => [{'address' => 'server.request.query'}]},
              'operator' => 'is_sqli'
            }
          ],
          'transformers' => ['removeNulls'],
          'on_match' => ['block']
        },
      ],
      'rules_compat' => [
        {
          'id' => 'api-001-100',
          'name' => 'JWT: No expiry is present',
          'tags' => {
            'type' => 'jwt',
            'category' => 'api_security',
            'confidence' => '0',
            'module' => 'business-logic'
          },
          'min_version' => '1.25.0',
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'server.request.jwt',
                    'key_path' => ['payload', 'exp']
                  }
                ]
              },
              'operator' => '!exists'
            }
          ],
          'transformers' => [],
          'output' => {
            'event' => false,
            'keep' => false,
            'attributes' => {'_dd.appsec.api.jwt.no_expiry' => {'value' => 1}}
          }
        }
      ],
      'processors' => [
        {
          "id" => "decode-auth-jwt",
          "generator" => "jwt_decode",
          "min_version" => "1.25.0",
          "parameters" => {
            "mappings" => [
              {
                "inputs" => [
                  {
                    "address" => "server.request.headers.no_cookies",
                    "key_path" => ["authorization"]
                  }
                ],
                "output" => "server.request.jwt"
              }
            ]
          },
          "evaluate" => true,
          "output" => false
        },
        {
          'id' => 'extract-token',
          'generator' => 'extract_schema',
          'conditions' => [
            {
              'operator' => 'equals',
              'parameters' => {
                'inputs' => [
                  {
                    'address' => 'waf.context.processor',
                    'key_path' => ['extract-schema']
                  }
                ],
                'type' => 'boolean',
                'value' => true
              }
            }
          ],
          'parameters' => {
            'mappings' => [
              {
                'inputs' => [{'address' => 'server.request.jwt'}],
                'output' => '_dd.appsec.s.req.jwt'
              }
            ],
            'scanners' => [
              {'tags' => {'category' => 'credentials'}},
              {'tags' => {'category' => 'pii'}}
            ]
          },
          'evaluate' => false,
          'output' => true
        }
      ]
    }
  end

  let(:app) do
    stack = Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      map '/test' do
        run ->(_) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
      end
    end

    stack.to_app
  end

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true

      c.appsec.enabled = true
      c.appsec.instrument :rack

      c.appsec.waf_timeout = 10_000_000 # in us
      c.appsec.ruleset = jwt_ruleset
      c.appsec.api_security.enabled = true

      c.remote.enabled = false
    end

    # NOTE: Don't reach the agent in any way
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  subject(:response) { last_response }

  context 'when JWT token is sent without expiration' do
    before { get('/test', {}, {'HTTP_AUTHORIZATION' => 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMn0.KMUFsIDTnFmyG3nMiGM6H9FNFUROf3wh7SmqJp-QV30'}) }

    it 'sets JWT related tags' do
      expect(response).to be_ok

      expect(http_service_entry_span.tags).to have_key('_dd.appsec.s.req.jwt')
      expect(http_service_entry_span.tags).to have_key('_dd.appsec.api.jwt.no_expiry')
    end
  end
end
