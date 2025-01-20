# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'

require 'rack/test'
require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack
      c.tracing.instrument :http

      c.appsec.enabled = true
      c.appsec.instrument :rack

      c.appsec.standalone.enabled = false
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

      map '/success' do
        run ->(_) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
      end
    end

    stack.to_app
  end

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

  let(:triggers) do
    appsec_json = spans
      .find { |span| span.metrics.fetch('_dd.top_level', -1.0) > 0.0 }
      .meta
      .fetch('_dd.appsec.json', '{}')
    JSON.parse(appsec_json).fetch('triggers', [])
  end

  describe 'HTTP service entry span metrics' do
    subject(:response) { last_response }

    context 'when no attack attempts detected' do
      before { get('/success', {}, { 'REMOTE_ADDR' => '127.0.0.1' }) }

      it { expect(response).to be_ok }
      it { expect(triggers).to be_empty }

      it 'contains span WAF metrics' do
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.timeouts')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.duration')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.duration_ext')
      end
    end

    context 'when attack detected by WAF' do
      before do
        get('/success', {}, { 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_USER_AGENT' => 'Nessus SOAP' })
      end

      it { expect(response).to be_ok }
      it { expect(triggers).to have(1).item }

      it 'contains span WAF metrics' do
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.timeouts')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.duration')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.duration_ext')
      end
    end

    # TODO Add ActiveRecord example
    # context 'when attack detected by RASP' do
    # end
  end
end
