require 'ddtrace'
require 'mysql2'
require 'helper'

class Mysql2Test < Minitest::Test
  MYSQL2_HOST = ENV.fetch('TEST_MYSQL2_HOST', '127.0.0.1').freeze
  MYSQL2_PORT = ENV.fetch('TEST_MYSQL2_PORT', '3306').freeze
  MYSQL2_DB = ENV.fetch('TEST_MYSQL_DB', 'test').freeze
  MYSQL2_USERNAME = ENV.fetch('TEST_MYSQL_USERNAME', 'root').freeze
  MYSQL2_PASSWORD = ENV.fetch('TEST_MYSQL_PASSWORD', 'root').freeze

  def setup
    Datadog.configure do |c|
      c.use :mysql2, service_name: 'my-sql'
    end

    @client = Mysql2::Client.new(
      host: MYSQL2_HOST,
      port: MYSQL2_PORT,
      database: MYSQL2_DB,
      username: MYSQL2_USERNAME,
      password: MYSQL2_PASSWORD
    )
    @tracer = get_test_tracer

    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def test_pin_attributes
    pin = Datadog::Pin.get_from(@client)
    assert_equal('my-sql', pin.service)
    assert_equal('mysql2', pin.app)
    assert_equal('db', pin.app_type)
  end

  def test_pin_disabled
    pin = Datadog::Pin.get_from(@client)
    pin.tracer.enabled = false
    @client.query('SELECT 1')
    spans = @tracer.writer.spans()
    assert_equal(0, spans.length)
  end

  def test_query
    @client.query('SELECT 1')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal(MYSQL2_DB, span.get_tag('mysql2.db.name'))
    assert_equal(MYSQL2_HOST, span.get_tag('out.host'))
    assert_equal(MYSQL2_PORT, span.get_tag('out.port'))
  end

  def test_failed_query
    assert_raises Mysql2::Error do
      @client.query('SELECT INVALID')
    end

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal(1, span.status)
    assert_equal("Unknown column 'INVALID' in 'field list'", span.get_tag('error.msg'))
  end
end
