# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Rack-request headers collection for identity.set_user' do
  include Rack::Test::Methods

  before do
    Datadog.configure do |c|
      c.tracing.enabled = true

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

    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)

    # NOTE: Don't reach the agent in any way
    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
    allow_any_instance_of(Datadog::Tracing::Transport::Traces::Transport).to receive(:native_events_supported?)
      .and_return(true)

    Datadog::AppSec::Contrib::Rack::Gateway::Watcher.watch_request_finish
  end

  after do
    Datadog.configuration.reset!
    Datadog.registry[:rack].reset_configuration!
  end

  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

  let(:app) do
    stack = Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      map '/with-identity-set-user' do
        run(
          lambda do |_env|
            Datadog::Kit::AppSec::Events.track_login_success(
              Datadog::Tracing.active_trace, Datadog::Tracing.active_span, user: { id: '42' }
            )

            [200, { 'Content-Type' => 'text/html' }, ['OK']]
          end
        )
      end

      map '/without-identity-set-user' do
        run ->(_env) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
      end
    end

    stack.to_app
  end

  subject(:response) { last_response }

  context 'when identity.set_user event was pushed' do
    before do
      headers = {
        'HTTP_UNKNOWNHEADER' => 'something',
        'HTTP_CF_CONNECTING_IPV6' => '2001:db8:3333:4444:5555:6666:1.2.3.4'
      }
      get('/with-identity-set-user', {}, headers)
    end

    it 'collects identity related request headers' do
      expect(response).to be_ok

      expect(http_service_entry_span.tags).not_to have_key('http.request.headers.unknownheader')
      expect(http_service_entry_span.tags).to include(
        'http.request.headers.cf-connecting-ipv6' => '2001:db8:3333:4444:5555:6666:1.2.3.4'
      )
    end
  end

  context 'when identity.set_user event was not pushed' do
    before do
      headers = {
        'HTTP_UNKNOWNHEADER' => 'something',
        'HTTP_CF_CONNECTING_IPV6' => '2001:db8:3333:4444:5555:6666:1.2.3.4'
      }
      get('/without-identity-set-user', {}, headers)
    end

    it 'does not collect identity related request headers' do
      expect(response).to be_ok

      expect(http_service_entry_span.tags).not_to have_key('http.request.headers.unknownheader')
      expect(http_service_entry_span.tags).not_to have_key('http.request.headers.cf-connecting-ipv6')
    end
  end
end
