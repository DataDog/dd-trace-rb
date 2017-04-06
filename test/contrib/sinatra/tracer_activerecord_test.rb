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
    app().settings.datadog_tracer.configure(tracer: tracer, enabled: true)

    conn = ActiveRecord::Base.establish_connection(adapter: 'sqlite3',
                                                   database: ':memory:')
    app().set :datadog_test_conn, conn

    Datadog::Monkey.patch_module(:active_record)

    super
  end

  def test_request
    post '/request'
    assert_equal(200, last_response.status)

    spans = @writer.spans()
    assert_equal(2, spans.length)

    span = spans[0]
    assert_equal('sqlite', span.service)
    assert_equal('SELECT 42', span.resource)
    assert_equal('sqlite', span.get_tag('active_record.db.vendor'))
    assert_equal(Datadog::Ext::SQL::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_equal(spans[1], span.parent)

    span = spans[1]
    assert_equal('sinatra', span.service)
    assert_equal('POST /request', span.resource)
    assert_equal('POST', span.get_tag(Datadog::Ext::HTTP::METHOD))
    assert_equal('/request', span.get_tag(Datadog::Ext::HTTP::URL))
    assert_equal(Datadog::Ext::HTTP::TYPE, span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end
end
