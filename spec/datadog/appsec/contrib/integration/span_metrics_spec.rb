# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'sqlite3'
require 'active_record'
require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'Span metrics integration test' do
  include Rack::Test::Methods

  before do
    stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.establish_connection({ adapter: 'sqlite3', database: ':memory:' })

      klass.connection.create_table 'users', force: :cascade do |t|
        t.string :name, null: false
      end

      # prevent internal sql requests from showing up
      klass.count
    end

    Datadog.configure do |c|
      c.tracing.enabled = true
      c.tracing.instrument :rack
      c.tracing.instrument :http

      c.appsec.enabled = true
      c.appsec.instrument :rack
      c.appsec.instrument :active_record

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
        run ->(_env) { [200, { 'Content-Type' => 'text/html' }, ['OK']] }
      end

      map '/rasp' do
        run(
          lambda do |env|
            request = Rack::Request.new(env)
            users = User.find_by_sql(
              "SELECT * FROM users WHERE name = '#{request.params['name']}'"
            )

            [200, { 'Content-Type' => 'text/html' }, [users.join(',')]]
          end
        )
      end
    end

    stack.to_app
  end

  let(:http_service_entry_span) do
    Datadog::Tracing::Transport::TraceFormatter.format!(trace)
    spans.find { |s| s.name == 'rack.request' }
  end

  describe 'HTTP service entry span metrics' do
    subject(:response) { last_response }

    context 'when WAF check triggered for HTTP request' do
      before do
        get('/waf', {}, { 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_USER_AGENT' => 'Nessus SOAP' })
      end

      it { expect(response).to be_ok }

      it 'contains span WAF metrics' do
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.timeouts')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.duration')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.waf.duration_ext')
      end
    end

    context 'when RASP check triggered for database query' do
      before do
        get('/rasp', { 'name' => "Bob'; OR 1=1" }, { 'REMOTE_ADDR' => '127.0.0.1' })
      end

      it { expect(response).to be_ok }

      it 'contains span RASP metrics' do
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.rasp.rule.eval')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.rasp.duration')
        expect(http_service_entry_span.metrics).to have_key('_dd.appsec.rasp.duration_ext')
        expect(http_service_entry_span.metrics).not_to have_key('_dd.appsec.rasp.timeout')
      end
    end
  end
end
