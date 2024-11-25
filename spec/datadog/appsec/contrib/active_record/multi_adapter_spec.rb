require 'datadog/appsec/spec_helper'
require 'active_record'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require 'mysql2'
require 'sqlite3'
require 'pg'

RSpec.describe 'AppSec ActiveRecord integration' do
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
    end
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

  shared_examples 'calls_waf_with_correct_arguments' do
    it 'calls waf with correct arguments' do
      expect(Datadog::AppSec.active_scope.processor_context).to(
        receive(:run).with(
          {},
          {
            'server.db.statement' => expected_db_statement,
            'server.db.system' => expected_db_system
          },
          Datadog.configuration.appsec.waf_timeout
        ).and_call_original
      )

      active_record_scope.to_a
    end
  end

  context 'mysql2 adapter' do
    let(:db_config) do
      {
        adapter: 'mysql2',
        database: ENV.fetch('TEST_MYSQL_DB', 'mysql'),
        host: ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'),
        password: ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root'),
        port: ENV.fetch('TEST_MYSQL_PORT', '3306')
      }
    end

    let(:expected_db_system) { 'mysql' }

    context 'when using .where' do
      let(:active_record_scope) { User.where(name: 'Bob') }
      let(:expected_db_statement) { "SELECT `users`.* FROM `users` WHERE `users`.`name` = 'Bob'" }

      include_examples 'calls_waf_with_correct_arguments'
    end

    context 'when using .find_by_sql' do
      let(:active_record_scope) { User.find_by_sql("SELECT * FROM users WHERE name = 'Bob'") }
      let(:expected_db_statement) { "SELECT * FROM users WHERE name = 'Bob'" }

      include_examples 'calls_waf_with_correct_arguments'
    end
  end

  context 'postgres adapter' do
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

    let(:expected_db_system) { 'postgresql' }

    context 'when using .where' do
      let(:active_record_scope) { User.where(name: 'Bob') }
      let(:expected_db_statement) { 'SELECT "users".* FROM "users" WHERE "users"."name" = $1' }

      include_examples 'calls_waf_with_correct_arguments'
    end

    context 'when using .find_by_sql' do
      let(:active_record_scope) { User.find_by_sql("SELECT * FROM users WHERE name = 'Bob'") }
      let(:expected_db_statement) { "SELECT * FROM users WHERE name = 'Bob'" }

      include_examples 'calls_waf_with_correct_arguments'
    end
  end

  context 'sqlite3 adapter' do
    let(:db_config) do
      {
        adapter: 'sqlite3',
        database: ':memory:'
      }
    end

    let(:expected_db_system) { 'sqlite' }

    context 'when using .where' do
      let(:active_record_scope) { User.where(name: 'Bob') }
      let(:expected_db_statement) { 'SELECT "users".* FROM "users" WHERE "users"."name" = ?' }

      include_examples 'calls_waf_with_correct_arguments'
    end

    context 'when using .find_by_sql' do
      let(:active_record_scope) { User.find_by_sql("SELECT * FROM users WHERE name = 'Bob'") }
      let(:expected_db_statement) { "SELECT * FROM users WHERE name = 'Bob'" }

      include_examples 'calls_waf_with_correct_arguments'
    end
  end
end
