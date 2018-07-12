require('sqlite3')
require('active_record')
require('contrib/sinatra/tracer_test_base')
class TracerActiveRecordTest < TracerTestBase
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
  class Article < ApplicationRecord
  end
  class TracerActiveRecordTestApp < Sinatra::Application
    post('/request') do
      conn = settings.datadog_test_conn
      conn.connection.execute('SELECT 42')
      ''
    end
    post('/cached_request') do
      Article.cache do
        Article.count
        Article.count
      end
    end
    get('/select_request') { Article.all.entries.to_s }
  end
  def app
    TracerActiveRecordTestApp
  end
  before do
    @writer = FauxWriter.new
    app.set(:datadog_test_writer, @writer)
    tracer = Datadog::Tracer.new(writer: @writer)
    Datadog.configuration.use(:sinatra, tracer: tracer)
    conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    app.set(:datadog_test_conn, conn)
    Datadog.configure do |c|
      c.tracer(hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'))
      c.use(:active_record)
    end
    super
  end
  def migrate_db
    Article.exists?
  rescue ActiveRecord::StatementInvalid
    ActiveRecord::Schema.define(version: 20180101000000) do
      create_table('articles', force: :cascade) do |t|
        t.string('title')
        t.datetime('created_at', null: false)
        t.datetime('updated_at', null: false)
      end
    end
  end
  it('request') do
    post('/request')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    # there should be at least 2 spans (span like "PRAGMA foreign_keys = ON" could appear)
    expect(spans.length).to be >= 2

    sinatra_span = spans[0]
    sqlite_span = spans[(spans.length - 1)]
    adapter_name = Datadog::Contrib::ActiveRecord::Utils.adapter_name
    database_name = Datadog::Contrib::ActiveRecord::Utils.database_name
    adapter_host = Datadog::Contrib::ActiveRecord::Utils.adapter_host
    adapter_port = Datadog::Contrib::ActiveRecord::Utils.adapter_port
    expect(sqlite_span.service).to(eq('sqlite'))
    expect(sqlite_span.resource).to(eq('SELECT 42'))
    expect(sqlite_span.get_tag('active_record.db.vendor')).to(eq(adapter_name))
    expect(sqlite_span.get_tag('active_record.db.name')).to(eq(database_name))
    unless adapter_host.nil?
      expect(sqlite_span.get_tag('out.host')).to(eq(adapter_host.to_s))
    end
    unless adapter_port.nil?
      expect(sqlite_span.get_tag('out.port')).to(eq(adapter_port.to_s))
    end
    expect(sqlite_span.span_type).to(eq(Datadog::Ext::SQL::TYPE))
    expect(sqlite_span.status).to(eq(0))
    expect(sqlite_span.parent).to(eq(sinatra_span))
    expect(sinatra_span.service).to(eq('sinatra'))
    expect(sinatra_span.resource).to(eq('POST /request'))
    expect(sinatra_span.get_tag(Datadog::Ext::HTTP::METHOD)).to(eq('POST'))
    expect(sinatra_span.get_tag(Datadog::Ext::HTTP::URL)).to(eq('/request'))
    expect(sinatra_span.span_type).to(eq(Datadog::Ext::HTTP::TYPE))
    expect(sinatra_span.status).to(eq(0))
    expect(sinatra_span.parent).to(be_nil)
  end
  it('cached tag') do
    migrate_db
    post('/cached_request')
    spans = all_spans.select do |s|
      s.resource.include?('SELECT COUNT(*) FROM "articles"')
    end
    expect(spans.length).to(eq(2))
    expect(spans.first.get_tag('active_record.db.cached')).to(be_nil)
    expect(spans.last.get_tag('active_record.db.cached')).to(eq('true'))
  end
  it('instantiation tracing') do
    skip unless Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
    migrate_db
    Article.create(title: 'Instantiation test')
    @writer.spans
    get('/select_request')
    expect(last_response.status).to(eq(200))
    spans = @writer.spans
    expect(spans.length).to(eq(3))
    instantiation_span, sinatra_span, sqlite_span = spans
    expect('active_record.instantiation').to(eq(instantiation_span.name))
    expect('custom').to(eq(instantiation_span.span_type))
    expect(sinatra_span.service).to(eq(instantiation_span.service))
    expect('TracerActiveRecordTest::Article').to(eq(instantiation_span.resource))
    expect('TracerActiveRecordTest::Article').to(eq(instantiation_span.get_tag('active_record.instantiation.class_name')))
    expect('1').to(eq(instantiation_span.get_tag('active_record.instantiation.record_count')))
    expect(instantiation_span.parent).to(eq(sinatra_span))
    expect(sqlite_span.parent).to(eq(sinatra_span))
  end

  private

  def all_spans
    @writer.spans(:keep)
  end
end
