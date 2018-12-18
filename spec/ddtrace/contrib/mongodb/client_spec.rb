require 'spec_helper'

require 'ddtrace'
require 'mongo'

RSpec.describe 'Mongo::Client instrumentation' do
  let(:tracer) { get_test_tracer }

  let(:client) { Mongo::Client.new(*client_options) }
  let(:client_options) { [["#{host}:#{port}"], { database: database }] }
  let(:host) { ENV.fetch('TEST_MONGODB_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_MONGODB_PORT', 27017) }
  let(:database) { 'test' }
  let(:collection) { :artists }

  let(:pin) { Datadog::Pin.get_from(client) }
  let(:spans) { tracer.writer.spans(:keep) }
  let(:span) { spans.first }

  def discard_spans!
    tracer.writer.spans
  end

  before(:each) do
    # Disable Mongo logging
    Mongo::Logger.logger.level = ::Logger::WARN

    Datadog.configure do |c|
      c.use :mongo
    end

    # Have to manually update this because its still
    # using global pin instead of configuration.
    # Remove this when we remove the pin.
    pin.tracer = tracer
  end

  # Clear data between tests
  after(:each) do
    client.database.drop
  end

  it 'evaluates the block given to the constructor' do
    expect { |b| Mongo::Client.new(*client_options, &b) }.to yield_control
  end

  context 'pin' do
    it 'has the correct attributes' do
      expect(pin.service).to eq('mongodb')
      expect(pin.app).to eq('mongodb')
      expect(pin.app_type).to eq('db')
    end

    context 'when the service is changed' do
      let(:service) { 'mongodb-primary' }
      before(:each) { pin.service = service }

      it 'produces spans with the correct service' do
        client[collection].insert_one(name: 'FKA Twigs')
        expect(spans).to have(1).items
        expect(spans.first.service).to eq(service)
      end
    end

    context 'when the tracer is disabled' do
      before(:each) { pin.tracer.enabled = false }

      it 'produces spans with the correct service' do
        client[collection].insert_one(name: 'FKA Twigs')
        expect(spans).to be_empty
      end
    end
  end

  # rubocop:disable Metrics/LineLength
  describe 'tracing' do
    shared_examples_for 'a MongoDB trace' do
      it 'has basic properties' do
        expect(spans).to have(1).items
        expect(span.service).to eq(pin.service)
        expect(span.span_type).to eq('mongodb')
        expect(span.get_tag('mongodb.db')).to eq(database)
        expect(span.get_tag('mongodb.collection')).to eq(collection.to_s)
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port.to_s)
      end
    end

    describe '#insert_one operation' do
      before(:each) { client[collection].insert_one(params) }

      context 'for a basic document' do
        let(:params) { { name: 'FKA Twigs' } }

        it_behaves_like 'a MongoDB trace'

        it 'has operation-specific properties' do
          expect(span.resource).to eq("{\"operation\"=>:insert, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"documents\"=>[{:name=>\"?\"}], \"ordered\"=>\"?\"}")
          expect(span.get_tag('mongodb.rows')).to eq('1')
        end
      end

      context 'for a document with an array' do
        let(:params) { { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] } }
        let(:collection) { :people }

        it_behaves_like 'a MongoDB trace'

        it 'has operation-specific properties' do
          expect(span.resource).to eq("{\"operation\"=>:insert, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"documents\"=>[{:name=>\"?\", :hobbies=>[\"?\"]}], \"ordered\"=>\"?\"}")
          expect(span.get_tag('mongodb.rows')).to eq('1')
        end
      end
    end

    describe '#insert_many operation' do
      before(:each) { client[collection].insert_many(params) }

      context 'for documents with arrays' do
        let(:params) do
          [
            { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] },
            { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
          ]
        end

        let(:collection) { :people }

        it_behaves_like 'a MongoDB trace'

        it 'has operation-specific properties' do
          expect(span.resource).to eq("{\"operation\"=>:insert, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"documents\"=>[{:name=>\"?\", :hobbies=>[\"?\"]}, \"?\"], \"ordered\"=>\"?\"}")
          expect(span.get_tag('mongodb.rows')).to eq('2')
        end
      end
    end

    describe '#find_all operation' do
      let(:collection) { :people }

      before(:each) do
        # Insert a document
        client[collection].insert_one(name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'])
        discard_spans!

        # Do #find_all operation
        client[collection].find.each do |document|
          # =>  Yields a BSON::Document.
        end
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>\"find\", \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"filter\"=>{}}")
        expect(span.get_tag('mongodb.rows')).to be nil
      end
    end

    describe '#find operation' do
      let(:collection) { :people }

      before(:each) do
        # Insert a document
        client[collection].insert_one(name: 'Steve', hobbies: ['hiking'])
        discard_spans!

        # Do #find operation
        result = client[collection].find(name: 'Steve').first[:hobbies]
        expect(result).to eq(['hiking'])
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>\"find\", \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"filter\"=>{\"name\"=>\"?\"}}")
        expect(span.get_tag('mongodb.rows')).to be nil
      end
    end

    describe '#update_one operation' do
      let(:collection) { :people }

      before(:each) do
        # Insert a document
        client[collection].insert_one(name: 'Sally', hobbies: ['skiing', 'stamp collecting'])
        discard_spans!

        # Do #update_one operation
        client[collection].update_one({ name: 'Sally' }, '$set' => { 'phone_number' => '555-555-5555' })
      end

      after(:each) do
        # Verify correctness of the operation
        expect(client[collection].find(name: 'Sally').first[:phone_number]).to eq('555-555-5555')
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>:update, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"updates\"=>[{\"q\"=>{\"name\"=>\"?\"}, \"u\"=>{\"$set\"=>{\"phone_number\"=>\"?\"}}, \"multi\"=>\"?\", \"upsert\"=>\"?\"}], \"ordered\"=>\"?\"}")
        expect(span.get_tag('mongodb.rows')).to eq('1')
      end
    end

    describe '#update_many operation' do
      let(:collection) { :people }
      let(:documents) do
        [
          { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] },
          { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
        ]
      end

      before(:each) do
        # Insert documents
        client[collection].insert_many(documents)
        discard_spans!

        # Do #update_many operation
        client[collection].update_many({}, '$set' => { 'phone_number' => '555-555-5555' })
      end

      after(:each) do
        # Verify correctness of the operation
        documents.each do |d|
          expect(client[collection].find(name: d[:name]).first[:phone_number]).to eq('555-555-5555')
        end
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>:update, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"updates\"=>[{\"q\"=>{}, \"u\"=>{\"$set\"=>{\"phone_number\"=>\"?\"}}, \"multi\"=>\"?\", \"upsert\"=>\"?\"}], \"ordered\"=>\"?\"}")
        expect(span.get_tag('mongodb.rows')).to eq('2')
      end
    end

    describe '#delete_one operation' do
      let(:collection) { :people }

      before(:each) do
        # Insert a document
        client[collection].insert_one(name: 'Sally', hobbies: ['skiing', 'stamp collecting'])
        discard_spans!

        # Do #delete_one operation
        client[collection].delete_one(name: 'Sally')
      end

      after(:each) do
        # Verify correctness of the operation
        expect(client[collection].find(name: 'Sally').count).to eq(0)
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>:delete, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"deletes\"=>[{\"q\"=>{\"name\"=>\"?\"}, \"limit\"=>\"?\"}], \"ordered\"=>\"?\"}")
        expect(span.get_tag('mongodb.rows')).to eq('1')
      end
    end

    describe '#delete_many operation' do
      let(:collection) { :people }
      let(:documents) do
        [
          { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] },
          { name: 'Sally', hobbies: ['skiing', 'stamp collecting'] }
        ]
      end

      before(:each) do
        # Insert documents
        client[collection].insert_many(documents)
        discard_spans!

        # Do #delete_many operation
        client[collection].delete_many(name: /$S*/)
      end

      after(:each) do
        # Verify correctness of the operation
        documents.each do |d|
          expect(client[collection].find(name: d[:name]).count).to eq(0)
        end
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>:delete, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"deletes\"=>[{\"q\"=>{\"name\"=>\"?\"}, \"limit\"=>\"?\"}], \"ordered\"=>\"?\"}")
        expect(span.get_tag('mongodb.rows')).to eq('2')
      end
    end

    describe '#drop operation' do
      let(:collection) { 1 } # Because drop operation doesn't have a collection

      before(:each) { client.database.drop }

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>:dropDatabase, \"database\"=>\"#{database}\", \"collection\"=>1}")
        expect(span.get_tag('mongodb.rows')).to be nil
      end
    end

    describe 'a failed query' do
      before(:each) { client[:artists].drop }

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        expect(span.resource).to eq("{\"operation\"=>:drop, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\"}")
        expect(span.get_tag('mongodb.rows')).to be nil
        expect(span.status).to eq(1)
        expect(span.get_tag('error.msg')).to eq('ns not found (26)')
      end
    end
  end
end
