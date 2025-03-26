# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'rack/contrib'
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
      c.appsec.ruleset = sqli_blocking_ruleset
      c.appsec.api_security.enabled = false
      c.appsec.api_security.sample_rate = 0.0

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

  let(:sqli_blocking_ruleset) do
    {
      'version' => '2.2',
      'metadata' => { 'rules_version' => '1.4.1' },
      'rules' => [
        {
          'id' => 'crs-942-100',
          'name' => 'SQL Injection Attack Detected via libinjection',
          'tags' => { 'type' => 'sql_injection', 'category' => 'attack_attempt' },
          'conditions' => [
            {
              'parameters' => {
                'inputs' => [
                  { 'address' => 'server.request.query' },
                  { 'address' => 'server.request.body' },
                  { 'address' => 'server.request.path_params' },
                  { 'address' => 'grpc.server.request.message' }
                ]
              },
              'operator' => 'is_sqli'
            }
          ],
          'transformers' => ['removeNulls'],
          'on_match' => ['block']
        },
      ]
    }
  end

  let(:app) do
    stack = Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      use Datadog::AppSec::Contrib::Rack::RequestMiddleware

      use Rack::JSONBodyParser
      use Datadog::AppSec::Contrib::Rack::RequestBodyMiddleware

      map '/test' do
        run ->(_) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
      end
    end

    stack.to_app
  end

  subject(:response) { last_response }

  context 'when deny and pass lists are not set' do
    before { get('/test', { q: '1 OR 1;' }, { 'HTTP_X_FORWARDED_FOR' => '1.2.3.4' }) }

    it { expect(response).to be_forbidden }
  end

  context 'when deny and pass lists are set' do
    before do
      Datadog.configure do |c|
        c.appsec.ip_denylist = ['1.2.3.4']
        c.appsec.ip_passlist = ['1.2.3.4']
      end

      get('/test', { q: '1 OR 1;' }, { 'HTTP_X_FORWARDED_FOR' => '1.2.3.4' })
    end

    it { expect(response).to be_ok }
  end

  context 'when pass list is set' do
    before do
      Datadog.configure { |c| c.appsec.ip_passlist = ['1.2.3.4'] }

      get('/test', { q: '1 OR 1;' }, { 'HTTP_X_FORWARDED_FOR' => '1.2.3.4' })
    end

    it { expect(response).to be_ok }
  end

  context 'when deny and pass lists are set and body contains SQLi' do
    before do
      Datadog.configure do |c|
        c.appsec.ip_denylist = ['1.2.3.4']
        c.appsec.ip_passlist = ['1.2.3.4']
      end

      body = { statement: <<~SQL }
        -- select count(*) from accounts where account_number is null
        select count(*) from payments where created_at >= '2025-03-01' and created_at < '2025-03-08'
      SQL

      post('/test', body.to_json, { 'CONTENT_TYPE' => 'application/json', 'HTTP_X_FORWARDED_FOR' => '1.2.3.4' })
    end

    it { expect(response).to be_ok }
  end
end
