require 'contrib/mongodb/test_helper'
require 'helper'

# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/LineLength
class MongoDBTest < Minitest::Test
  MONGO_HOST = '127.0.0.1'.freeze
  MONGO_PORT = 57017
  MONGO_DB = 'test'.freeze

  def setup
    Datadog.configure do |c|
      c.use :mongo
    end

    # disable Mongo logging
    Mongo::Logger.logger.level = ::Logger::WARN

    # initialize the client and overwrite the default tracer
    @client = Mongo::Client.new(["#{MONGO_HOST}:#{MONGO_PORT}"], database: MONGO_DB)
    @tracer = get_test_tracer()
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def teardown
    # clear intermediate data
    @client.database.drop
  end

  def test_constructor_signature
    executed = false
    Mongo::Client.new(["#{MONGO_HOST}:#{MONGO_PORT}"], database: MONGO_DB) do |_self|
      # be sure that the block is evaluated
      executed = true
    end
    assert(executed, 'the constructor block is not executed')
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
    @client[:artists].insert_one(name: 'FKA Twigs')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('mongodb-primary', span.service)
  end

  def test_pin_disabled
    pin = Datadog::Pin.get_from(@client)
    pin.tracer.enabled = false
    @client[:artists].insert_one(name: 'FKA Twigs')
    spans = @tracer.writer.spans()
    assert_equal(0, spans.length)
  end

  def test_insert_operation
    @client[:artists].insert_one(name: 'FKA Twigs')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:insert, :database=>"test", :collection=>"artists", "documents"=>{:name=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('artists', span.get_tag('mongodb.collection'))
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
    assert_equal('{:operation=>:dropDatabase, :database=>"test", :collection=>1}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('1', span.get_tag('mongodb.collection'))
    assert_nil(span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end

  def test_insert_array_operation
    @client[:people].insert_one(name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'])
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:insert, :database=>"test", :collection=>"people", "documents"=>{:name=>"?", :hobbies=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_equal('1', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end

  def test_insert_many_array_operation
    docs = [
      { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] },
      { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
    ]

    @client[:people].insert_many(docs)
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:insert, :database=>"test", :collection=>"people", "documents"=>{:name=>"?", :hobbies=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_equal('2', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end

  def test_find_all
    # prepare the test case
    doc = { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] }
    @client[:people].insert_one(doc)
    @tracer.writer.spans()

    # do a find in all and consume the database
    collection = @client[:people]
    collection.find.each do |document|
      # =>  Yields a BSON::Document.
    end
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>"find", :database=>"test", :collection=>"people", "filter"=>{}}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_nil(span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end

  def test_find_matching_document
    # prepare the test case
    doc = { name: 'Steve', hobbies: ['hiking'] }
    @client[:people].insert_one(doc)
    @tracer.writer.spans()

    # find and check the correct result
    collection = @client[:people]
    assert_equal(['hiking'], collection.find(name: 'Steve').first[:hobbies])
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>"find", :database=>"test", :collection=>"people", "filter"=>{"name"=>"?"}}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_nil(span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end

  def test_update_one_document
    # prepare the test case
    doc = { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
    collection = @client[:people]
    collection.insert_one(doc)
    @tracer.writer.spans()

    # update with a new field
    collection.update_one({ name: 'Sally' }, '$set' => { 'phone_number' => '555-555-5555' })
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:update, :database=>"test", :collection=>"people", "updates"=>{"q"=>{"name"=>"?"}, "u"=>{"$set"=>{"phone_number"=>"?"}}, "multi"=>"?", "upsert"=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_equal('1', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
    # validity check
    assert_equal('555-555-5555', collection.find(name: 'Sally').first[:phone_number])
  end

  def test_update_many_documents
    # prepare the test case
    docs = [
      { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] },
      { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
    ]

    collection = @client[:people]
    collection.insert_many(docs)
    @tracer.writer.spans()

    # update with a new field
    collection.update_many({}, '$set' => { 'phone_number' => '555-555-5555' })
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:update, :database=>"test", :collection=>"people", "updates"=>{"q"=>{}, "u"=>{"$set"=>{"phone_number"=>"?"}}, "multi"=>"?", "upsert"=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_equal('2', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
    # validity checks
    assert_equal('555-555-5555', collection.find(name: 'Sally').first[:phone_number])
    assert_equal('555-555-5555', collection.find(name: 'Steve').first[:phone_number])
  end

  def test_delete_one_document
    # prepare the test case
    doc = { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
    collection = @client[:people]
    collection.insert_one(doc)
    @tracer.writer.spans()

    # update with a new field
    collection.delete_one(name: 'Sally')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:delete, :database=>"test", :collection=>"people", "deletes"=>{"q"=>{"name"=>"?"}, "limit"=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_equal('1', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
    # validity check
    assert_equal(0, collection.find(name: 'Sally').count)
  end

  def test_delete_many_documents
    # prepare the test case
    docs = [
      { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] },
      { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
    ]

    collection = @client[:people]
    collection.insert_many(docs)
    @tracer.writer.spans()

    # update with a new field
    collection.delete_many(name: /$S*/)
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:delete, :database=>"test", :collection=>"people", "deletes"=>{"q"=>{"name"=>"?"}, "limit"=>"?"}, "ordered"=>"?"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('people', span.get_tag('mongodb.collection'))
    assert_equal('2', span.get_tag('mongodb.rows'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
    # validity check
    assert_equal(0, collection.find(name: 'Sally').count)
    assert_equal(0, collection.find(name: 'Steve').count)
  end

  def test_failed_queries
    # do an invalid operation that results with a failed command
    @client[:artists].drop
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    # check fields
    assert_equal('{:operation=>:drop, :database=>"test", :collection=>"artists"}', span.resource)
    assert_equal('mongodb', span.service)
    assert_equal('mongodb', span.span_type)
    assert_equal('test', span.get_tag('mongodb.db'))
    assert_equal('artists', span.get_tag('mongodb.collection'))
    assert_nil(span.get_tag('mongodb.rows'))
    assert_equal(1, span.status)
    assert_equal('ns not found (26)', span.get_tag('error.msg'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('57017', span.get_tag('out.port'))
  end
end
