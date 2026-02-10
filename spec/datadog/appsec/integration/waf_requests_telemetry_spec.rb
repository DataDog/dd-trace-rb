# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'WAF requests telemetry' do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack
      c.tracing.instrument :http

      c.appsec.enabled = true
      c.appsec.instrument :rack

      c.appsec.waf_timeout = 10_000_000 # in us
      c.appsec.ip_passlist = []
      c.appsec.ip_denylist = []
      c.appsec.user_id_denylist = []
      c.appsec.api_security.enabled = false
      c.appsec.api_security.sample_rate = 0.0

      c.appsec.ruleset = {
        rules: [
          {
            id: "ua0-600-10x",
            name: "Nessus",
            tags: {
              type: "attack_tool",
              category: "attack_attempt",
              cwe: "200",
              capec: "1000/118/169",
              tool_name: "Nessus",
              confidence: "1",
              module: "waf"
            },
            conditions: [
              {
                parameters: {
                  inputs: [
                    {
                      address: "server.request.headers.no_cookies",
                      key_path: ["user-agent"]
                    }
                  ],
                  regex: "(?i)^Nessus(/|([ :]+SOAP))"
                },
                operator: "match_regex"
              }
            ],
            transformers: []
          }
        ]
      }

      c.remote.enabled = false
    end

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  let(:app) do
    stack = Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      map '/waf' do
        run ->(_env) { [200, {'Content-Type' => 'text/html'}, ['OK']] }
      end
    end

    stack.to_app
  end

  describe 'appsec.waf.requests telemetry' do
    context 'when WAF check triggered for HTTP request' do
      it 'exports correct tags' do
        allow(Datadog::AppSec.telemetry).to receive(:inc)

        get('/waf', {}, {'REMOTE_ADDR' => '127.0.0.1', 'HTTP_USER_AGENT' => 'Nessus SOAP'})

        expect(Datadog::AppSec.telemetry).to have_received(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
          tags: hash_including(
            rule_triggered: 'true',
            waf_error: 'false',
            waf_timeout: 'false',
            request_blocked: 'false',
            rate_limited: 'false'
          )
        )
      end
    end

    context 'when WAF check did not trigger for HTTP request' do
      it 'exports correct tags' do
        allow(Datadog::AppSec.telemetry).to receive(:inc)

        get('/waf', {}, {})

        expect(Datadog::AppSec.telemetry).to have_received(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
          tags: hash_including(
            rule_triggered: 'false',
            waf_error: 'false',
            waf_timeout: 'false',
            request_blocked: 'false'
          )
        )
      end
    end
  end
end
