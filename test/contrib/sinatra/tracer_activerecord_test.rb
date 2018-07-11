require 'sqlite3'
require 'active_record'

require 'contrib/sinatra/tracer_test_base'

class TracerActiveRecordTest < TracerTestBase
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class Article < ApplicationRecord
  end

  class TracerActiveRecordTestApp < Sinatra::Application
    post '/request' do
      conn = settings.datadog_test_conn
      conn.connection.execute('SELECT 42')
      ''
    end

    post '/cached_request' do
      Article.cache do
        # Do two queries (second should cache.)
        Article.count
        Article.count
      end
    end

    get '/select_request' do
      Article.all.entries.to_s
    end
  end

  def app
    TracerActiveRecordTestApp
  end

  def setup
    @writer = FauxWriter.new()
    app().set :datadog_test_writer, @writer

    tracer = Datadog::Tracer.new(writer: @writer)
    Datadog.configuration.use(:sinatra, tracer: tracer)

    conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                   database: ':memory:')
    app().set :datadog_test_conn, conn

    Datadog.configure do |c|
      c.tracer hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost')
      c.use :active_record
    end

    super
  end

  def migrate_db
    Article.exists?
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Schema.define(version: 20180101000000) do
      create_table 'articles', force: :cascade do |t|
        t.string   'title'
        t.datetime 'created_at', null: false
        t.datetime 'updated_at', null: false
      end
    end
  end

  # rubocop:disable Metrics/AbcSize
  def test_request
    post '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_operator(2, :<=, spans.length,
                    'there should be at least 2 spans (span like "PRAGMA foreign_keys = ON" could appear)')

    sinatra_span = spans[0]
    sqlite_span = spans[spans.length - 1]

    adapter_name = Datadog::Contrib::ActiveRecord::Utils.adapter_name
    database_name = Datadog::Contrib::ActiveRecord::Utils.database_name
    adapter_host = Datadog::Contrib::ActiveRecord::Utils.adapter_host
    adapter_port = Datadog::Contrib::ActiveRecord::Utils.adapter_port

    assert_equal('sqlite', sqlite_span.service)
    assert_equal('SELECT 42', sqlite_span.resource)
    assert_equal(adapter_name, sqlite_span.get_tag('active_record.db.vendor'))
    assert_equal(database_name, sqlite_span.get_tag('active_record.db.name'))
    assert_equal(adapter_host.to_s, sqlite_span.get_tag('out.host')) unless adapter_host.nil?
    assert_equal(adapter_port.to_s, sqlite_span.get_tag('out.port')) unless adapter_port.nil?
    assert_equal(Datadog::Ext::SQL::TYPE, sqlite_span.span_type)
    assert_equal(0, sqlite_span.status)
    assert_equal(sinatra_span, sqlite_span.parent)

    assert_equal('sinatra', sinatra_span.service)
    assert_equal('POST /request', sinatra_span.resource)
    assert_equal('POST', sinatra_span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/request', sinatra_span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, sinatra_span.span_type)
    assert_equal(0, sinatra_span.status)
    assert_nil(sinatra_span.parent)
  end

  # Testing AR query caching requires use of a model.
  # Create a model, query it a few times, make sure cached tag gets set.
  def test_cached_tag
    # Make sure Article table exists
    migrate_db

    # Do query with cached query
    post '/cached_request'

    # Assert correct number of spans (ignoring transactions, etc.)
    spans = all_spans.select { |s| s.resource.include?('SELECT COUNT(*) FROM "articles"') }
    assert_equal(2, spans.length)

    # Assert cached flag not present on first query
    assert_nil(spans.first.get_tag('active_record.db.cached'))

    # Assert cached flag set correctly on second query
    assert_equal('true', spans.last.get_tag('active_record.db.cached'))
  end

  def test_instantiation_tracing
    # Only supported in Rails 4.2+
    skip unless Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?

    # Make sure Article table exists
    migrate_db
    Article.create(title: 'Instantiation test')
    @writer.spans # Clear spans

    # Run query
    get '/select_request'
    assert_equal(200, last_response.status)

    spans = @writer.spans
    assert_equal(3, spans.length)

    instantiation_span, sinatra_span, sqlite_span = spans

    assert_equal(instantiation_span.name, 'active_record.instantiation')
    assert_equal(instantiation_span.span_type, 'custom')
    assert_equal(instantiation_span.service, sinatra_span.service)
    assert_equal(instantiation_span.resource, 'TracerActiveRecordTest::Article')
    assert_equal(instantiation_span.get_tag('active_record.instantiation.class_name'), 'TracerActiveRecordTest::Article')
    assert_equal(instantiation_span.get_tag('active_record.instantiation.record_count'), '1')
    assert_equal(sinatra_span, instantiation_span.parent)
    assert_equal(sinatra_span, sqlite_span.parent)
  end

  private

  def all_spans
    @writer.spans(:keep)
  end
end
