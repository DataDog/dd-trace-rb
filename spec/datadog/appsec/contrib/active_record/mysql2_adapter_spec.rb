# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'active_record'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'mysql2'
end

RSpec.describe 'AppSec ActiveRecord integration for Mysql2 adapter' do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }
  let(:context) { Datadog::AppSec::Context.new(trace, span, processor) }

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
      adapter: 'mysql2',
      database: ENV.fetch('TEST_MYSQL_DB', 'mysql'),
      host: ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'),
      password: ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root'),
      port: ENV.fetch('TEST_MYSQL_PORT', '3306')
    }
  end

  before do
    Datadog.configure do |c|
      c.appsec.enabled = true
      c.appsec.instrument :active_record
    end

    Datadog::AppSec::Context.activate(context)

    raise_on_rails_deprecation!
  end

  after do
    Datadog.configuration.reset!

    Datadog::AppSec::Context.deactivate
    processor.finalize
  end

  context 'when RASP is disabled' do
    before do
      allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(false)
    end

    it 'does not call waf when querying using .where' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      User.where(name: 'Bob').to_a
    end

    it 'does not call waf when querying using .find_by_sql' do
      expect(Datadog::AppSec.active_context).not_to receive(:run_rasp)

      User.find_by_sql("SELECT * FROM users WHERE name = 'Bob'").to_a
    end
  end

  context 'when RASP is enabled' do
    before do
      allow(Datadog::AppSec).to receive(:rasp_enabled?).and_return(true)
    end

    it 'calls waf with correct arguments when querying using .where' do
      expect(Datadog::AppSec.active_context).to(
        receive(:run_rasp).with(
          Datadog::AppSec::Ext::RASP_SQLI,
          {},
          {
            'server.db.statement' => "SELECT `users`.* FROM `users` WHERE `users`.`name` = 'Bob'",
            'server.db.system' => 'mysql2'
          },
          Datadog.configuration.appsec.waf_timeout
        ).and_call_original
      )

      User.where(name: 'Bob').to_a
    end

    it 'calls waf with correct arguments when querying using .find_by_sql' do
      expect(Datadog::AppSec.active_context).to(
        receive(:run_rasp).with(
          Datadog::AppSec::Ext::RASP_SQLI,
          {},
          {
            'server.db.statement' => "SELECT * FROM users WHERE name = 'Bob'",
            'server.db.system' => 'mysql2'
          },
          Datadog.configuration.appsec.waf_timeout
        ).and_call_original
      )

      User.find_by_sql("SELECT * FROM users WHERE name = 'Bob'").to_a
    end

    context 'when waf result is a match' do
      let(:result) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [],
          actions: { 'generate_stack' => { 'stack_id' => 'some-id' } },
          derivatives: {},
          timeout: false,
          duration_ns: 0,
          duration_ext_ns: 0
        )
      end

      before do
        allow(Datadog::AppSec.active_context).to receive(:run_rasp).and_return(result)
      end

      it 'adds an event to context events' do
        expect { User.where(name: 'Bob').to_a }.to change(Datadog::AppSec.active_context.events, :size).by(1)
      end
    end
  end
end
