# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/appsec/spec_helper'
require 'rack/test'

require 'sqlite3'
require 'active_record'
require 'datadog/tracing'
require 'datadog/appsec'

RSpec.describe 'ActiveRecord SQL Injection' do
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

      c.appsec.ruleset = {
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
                  resource: [{ address: 'server.db.statement' }],
                  params: [{ address: 'server.request.query' }],
                  db_type: [{ address: 'server.db.system' }]
                }
              }
            ],
            on_match: ['block']
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

      map '/rasp' do
        run(
          lambda do |env|
            request = Rack::Request.new(env)
            users = User.find_by_sql(
              "SELECT * FROM users WHERE name = '#{request.params['name']}'"
            )

            [200, { 'Content-Type' => 'application/json' }, [users.to_json]]
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

  context 'when RASP check triggered for database query' do
    before do
      get('/rasp', { 'name' => "Bob'; OR 1=1" }, { 'REMOTE_ADDR' => '127.0.0.1' })
    end

    it { expect(last_response).to be_forbidden }
  end
end
