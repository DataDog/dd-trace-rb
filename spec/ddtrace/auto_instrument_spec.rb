require 'datadog/tracing/contrib/support/spec_helper'
require 'rack/test'

require 'sinatra/base'
require 'active_record'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'sqlite3'
end

# Loading 'ddtrace/auto_instrument' has side effects and can't
# easily be undone. This test should run on its own process.
RSpec.describe 'Auto Instrumentation of non Rails' do
  include Rack::Test::Methods

  before do
    RSpec.configure do |config|
      unless config.files_to_run.one?
        raise 'auto_instrument_spec.rb should be run on a separate RSpec process, do not run it together with other specs'
      end
    end
    require 'ddtrace/auto_instrument'
  end

  after { Datadog.registry[:sinatra].reset_configuration! }

  shared_context 'ActiveRecord database' do
    let(:application_record_class) do
      Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
    end

    let(:model_class) do
      stub_const('Article', Class.new(application_record_class))
    end

    def migrate_db
      model_class.exists?
    rescue ActiveRecord::StatementInvalid
      ActiveRecord::Schema.define(version: 20180101000000) do
        create_table 'articles', force: :cascade do |t|
          t.string   'title'
          t.datetime 'created_at', null: false
          t.datetime 'updated_at', null: false
        end
      end
    end

    before { migrate_db }
  end

  describe 'request which runs a query' do
    subject(:response) { post '/' }

    let(:app) do
      conn = connection

      Class.new(Sinatra::Application) do
        post '/' do
          conn.connection.execute('SELECT 42')
          ''
        end
      end
    end

    let(:connection) do
      ActiveRecord::Base.establish_connection(
        adapter: 'sqlite3',
        database: ':memory:'
      ).tap do |conn|
        conn.connection.execute("SELECT 'bootstrap query'")
      end
    end

    let(:route_span) { spans.find { |s| s.name == Datadog::Tracing::Contrib::Sinatra::Ext::SPAN_ROUTE } }
    let(:sqlite_span) { spans.find { |s| s.resource == 'SELECT 42' } }

    let(:adapter_name) { Datadog::Tracing::Contrib::ActiveRecord::Utils.adapter_name }
    let(:database_name) { Datadog::Tracing::Contrib::ActiveRecord::Utils.database_name }
    let(:adapter_host) { Datadog::Tracing::Contrib::ActiveRecord::Utils.adapter_host }
    let(:adapter_port) { Datadog::Tracing::Contrib::ActiveRecord::Utils.adapter_port }

    it 'auto_instruments all relevant gems automatically' do
      is_expected.to be_ok
      expect(spans).to have_at_least(2).items

      expect(sqlite_span.name).to eq('sqlite.query')
      expect(sqlite_span.service).to eq('sqlite')
      expect(sqlite_span.resource).to eq('SELECT 42')
      expect(sqlite_span.get_tag('active_record.db.vendor')).to eq('sqlite')
      expect(sqlite_span.get_tag('active_record.db.name')).to eq(':memory:')
      expect(sqlite_span.get_tag('out.host')).to eq(adapter_host.to_s) unless adapter_host.nil?
      expect(sqlite_span.get_tag('out.port')).to eq(adapter_port.to_s) unless adapter_port.nil?
      expect(sqlite_span.span_type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
      expect(sqlite_span).to_not have_error
      expect(sqlite_span.parent_id).to eq(route_span.span_id)

      expect(route_span).to_not have_error
    end
  end
end

RSpec.describe 'LOADED variable' do
  subject(:auto_instrument) { load 'ddtrace/auto_instrument.rb' }
  it do
    auto_instrument
    expect(Datadog::AutoInstrument::LOADED).to eq(true)
  end
end

RSpec.describe 'Profiler startup' do
  subject(:auto_instrument) { load 'ddtrace/auto_instrument.rb' }

  it 'starts the profiler' do
    expect(Datadog::Profiling).to receive(:start_if_enabled)
    auto_instrument
  end
end
