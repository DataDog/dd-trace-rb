require 'sqlite3'
require 'active_record'

require 'contrib/sinatra/tracer_test_base'

class TracerActiveRecordTest < TracerTestBase
  class TracerActiveRecordTestApp < Sinatra::Application
    post '/request' do
      conn = settings.datadog_test_conn
      conn.connection.execute('SELECT 42')
      ''
    end
  end

  def app
    TracerActiveRecordTestApp
  end

  def setup
    @writer = FauxWriter.new()
    app().set :datadog_test_writer, @writer

    tracer = Datadog::Tracer.new(writer: @writer)
    Datadog.configuration.use(:sinatra, tracer: tracer, enabled: true)

    conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                   database: ':memory:')
    app().set :datadog_test_conn, conn

    Datadog.configuration.use(:active_record)

    super
  end

  def test_request
    post '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_operator(2, :<=, spans.length,
                    'there should be at least 2 spans (span like "PRAGMA foreign_keys = ON" could appear)')

    sinatra_span = spans[0]
    sqlite_span = spans[spans.length - 1]

    assert_equal('sqlite', sqlite_span.service)
    assert_equal('SELECT 42', sqlite_span.resource)
    assert_equal('sqlite', sqlite_span.get_tag('active_record.db.vendor'))
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
end
