require 'ddtrace/contrib/support/spec_helper'
require 'rack/test'

require 'sinatra/base'
require 'active_record'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'sqlite3'
end

require 'ddtrace'
require 'ddtrace/contrib/sinatra/tracer'

RSpec.describe 'Sinatra instrumentation with ActiveRecord' do
  include Rack::Test::Methods

  let(:options) { {} }

  before do
    Datadog.configure do |c|
      c.use :sinatra, options
      c.use :active_record, options
    end
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

    let(:route_span) { spans.find { |s| s.name == Datadog::Contrib::Sinatra::Ext::SPAN_ROUTE } }
    let(:sqlite_span) { spans.find { |s| s.resource == 'SELECT 42' } }

    let(:adapter_name) { Datadog::Contrib::ActiveRecord::Utils.adapter_name }
    let(:database_name) { Datadog::Contrib::ActiveRecord::Utils.database_name }
    let(:adapter_host) { Datadog::Contrib::ActiveRecord::Utils.adapter_host }
    let(:adapter_port) { Datadog::Contrib::ActiveRecord::Utils.adapter_port }

    it do
      is_expected.to be_ok
      expect(spans).to have_at_least(2).items

      expect(sqlite_span.name).to eq('sqlite.query')
      expect(sqlite_span.service).to eq('sqlite')
      expect(sqlite_span.resource).to eq('SELECT 42')

      expect(sqlite_span.get_tag('active_record.db.vendor')).to eq('sqlite')
      expect(sqlite_span.get_tag('active_record.db.name')).to eq(':memory:')
      expect(sqlite_span.get_tag('out.host')).to eq(adapter_host.to_s) unless adapter_host.nil?
      expect(sqlite_span.get_tag('out.port')).to eq(adapter_port.to_s) unless adapter_port.nil?
      expect(sqlite_span.span_type).to eq(Datadog::Ext::SQL::TYPE)
      expect(sqlite_span).to_not have_error
      expect(sqlite_span.parent).to eq(route_span)

      expect(route_span).to_not have_error
    end
  end
end
