require 'byebug'
require 'contrib/mongodb/test_helper'
require 'helper'

class MongoDBTest < Minitest::Test
  MONGO_HOST = '127.0.0.1'.freeze
  MONGO_PORT = 57017
  MONGO_DB = 'test'.freeze

  def setup
    # initialize the client and overwrite the default tracer
    @client = Mongo::Client.new(["#{MONGO_HOST}:#{MONGO_PORT}"], :database => MONGO_DB)
    @tracer = get_test_tracer()
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def teardown
    # clear intermediate data
    @client.database.drop
  end

  def test_pin_attributes
    # the client must have a PIN set
    pin = Datadog::Pin.get_from(@client)
    assert_equal('mongodb', pin.service)
    assert_equal('mongodb', pin.app)
    assert_equal('db', pin.app_type)
  end

  def test_pin_service_change
    pin = Datadog::Pin.get_from(@client)
    pin.service = 'mongodb-primary'
    @client[:artists].insert_one({ :name => 'FKA Twigs' })
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('mongodb-primary', span.service)
  end

  def test_insert_operation
    @client[:artists].insert_one({ :name => 'FKA Twigs' })
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('insert artists [{:name=>"?"}]', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('artists', span.get_tag('mongodb.collection'))
    assert_equal('[{:name=>"?"}]', span.get_tag('mongodb.documents'))
    assert_equal('1', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end

  def test_drop_operation
    @client.database.drop
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('dropDatabase', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_nil(span.get_tag('mongodb.collection'))
    assert_nil(span.get_tag('mongodb.documents'))
    assert_nil(span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end
end
