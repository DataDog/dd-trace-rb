# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'active_record'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'pg'
end

RSpec.describe 'AppSec ActiveRecord integration for Postgresql adapter' do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }
  let(:context) { processor.new_context }

  let(:span) { Datadog::Tracing::SpanOperation.new('root') }
  let(:trace) { Datadog::Tracing::TraceOperation.new }

  let!(:user_class) do
    stub_const('User', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.establish_connection(db_config)

      klass.connection.create_table 'users', force: :cascade do |t|
        t.string :name, null: false
        t.string :email, null: false
        t.timestamps
      end

      # prevent internal sql requests from showing up
      klass.count
      klass.first
    end
  end

  let(:db_config) do
    {
      adapter: 'postgresql',
      database: ENV.fetch('TEST_POSTGRES_DB', 'postgres'),
      host: ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1'),
      port: ENV.fetch('TEST_POSTGRES_PORT', 5432),
      username: ENV.fetch('TEST_POSTGRES_USER', 'postgres'),
      password: ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres')
    }
  end

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :active_record
    end

    Datadog::AppSec::Scope.activate_scope(trace, span, processor)

    raise_on_rails_deprecation!
  end

  after do
    Datadog.configuration.reset!

    Datadog::AppSec::Scope.deactivate_scope
    processor.finalize
  end

  it 'calls waf with correct arguments when querying using .where' do
    expected_db_statement = if PlatformHelpers.jruby?
                              'SELECT "users".* FROM "users" WHERE "users"."name" = ?'
                            else
                              'SELECT "users".* FROM "users" WHERE "users"."name" = $1'
                            end

    expect(Datadog::AppSec.active_scope.processor_context).to(
      receive(:run).with(
        {},
        {
          'server.db.statement' => expected_db_statement,
          'server.db.system' => 'postgresql'
        },
        Datadog.configuration.appsec.waf_timeout
      ).and_call_original
    )

    User.where(name: 'Bob').to_a
  end

  it 'calls waf with correct arguments when querying using .find_by_sql' do
    expect(Datadog::AppSec.active_scope.processor_context).to(
      receive(:run).with(
        {},
        {
          'server.db.statement' => "SELECT * FROM users WHERE name = 'Bob'",
          'server.db.system' => 'postgresql'
        },
        Datadog.configuration.appsec.waf_timeout
      ).and_call_original
    )

    User.find_by_sql("SELECT * FROM users WHERE name = 'Bob'").to_a
  end

  it 'adds an event to processor context if waf status is :match' do
    expect(Datadog::AppSec.active_scope.processor_context).to(
      receive(:run).and_return(instance_double(Datadog::AppSec::WAF::Result, status: :match, actions: {}))
    )

    expect(Datadog::AppSec.active_scope.processor_context.events).to receive(:<<).and_call_original

    User.where(name: 'Bob').to_a
  end
end
