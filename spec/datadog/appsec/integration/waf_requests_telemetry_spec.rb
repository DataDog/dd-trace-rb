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
      c.appsec.ruleset = :recommended
      c.appsec.api_security.enabled = false
      c.appsec.api_security.sample_rate = 0.0

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
    subject(:response) { last_response }

    context 'when WAF check triggered for HTTP request' do
      it 'exports correct tags' do
        expect(Datadog::AppSec.telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
          tags: hash_including(
            rule_triggered: 'true',
            waf_error: 'false',
            waf_timeout: 'false',
            request_blocked: 'false',
            rate_limited: 'false'
          )
        )

        get('/waf', {}, {'REMOTE_ADDR' => '127.0.0.1', 'HTTP_USER_AGENT' => 'Nessus SOAP'})
      end
    end

    context 'when WAF check did not trigger for HTTP request' do
      it 'exports correct tags' do
        expect(Datadog::AppSec.telemetry).to receive(:inc).with(
          Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
          tags: hash_including(
            rule_triggered: 'false',
            waf_error: 'false',
            waf_timeout: 'false',
            request_blocked: 'false'
          )
        )

        get('/waf', {}, {})
      end
    end
  end
end
