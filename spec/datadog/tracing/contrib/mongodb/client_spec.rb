require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'ddtrace'
require 'mongo'

RSpec.describe 'Mongo::Client instrumentation' do
  let(:configuration_options) { {} }
  # Clear data between tests
  let(:drop_database?) { true }

  let(:client) { Mongo::Client.new(["#{host}:#{port}"], client_options) }
  let(:client_options) { { database: database } }
  let(:host) { ENV.fetch('TEST_MONGODB_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_MONGODB_PORT', 27017).to_i }
  let(:database) { 'test' }
  let(:collection) { :artists }

  let(:mongo_gem_version) { Gem.loaded_specs['mongo'].version }

  before do
    # Disable Mongo logging
    Mongo::Logger.logger.level = ::Logger::WARN

    Datadog.configure do |c|
      c.tracing.instrument :mongo, configuration_options
    end
  end

  around do |example|
    without_warnings do
      # Reset before and after each example; don't allow global state to linger.
      Datadog.registry[:mongo].reset_configuration!
      example.run
      Datadog.registry[:mongo].reset_configuration!
      client.database.drop if drop_database?
      client.close
    end
  end

  context 'when the client is configured with a block' do
    after { @client.close }

    it 'evaluates the block given to the constructor' do
      expect { |b| @client = Mongo::Client.new(["#{host}:#{port}"], client_options, &b) }.to yield_control
    end
  end

  context 'when the client is configured' do
    context 'with a different service name' do
      let(:service) { 'mongodb-primary' }

      before { Datadog.configure_onto(client, service_name: service) }

      subject { client[collection].insert_one(name: 'FKA Twigs') }

      it 'produces spans with the correct service' do
        subject
        expect(spans).to have(1).items
        expect(spans.first.service).to eq(service)
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end
    end

    context 'with a different service name using describes option' do
      let(:primary_service) { 'mongodb-primary' }
      let(:secondary_service) { 'mongodb-secondary' }
      let(:secondary_client) { Mongo::Client.new(["#{secondary_host}:#{port}"], client_options) }
      # TODO: This tests doesn't work if TEST_MONGODB_HOST is set to anything other than 127.0.0.1
      #       We should fix this... maybe do a more clever IP resolve or something?
      let(:secondary_host) { 'localhost' }

      before do
        Datadog.configure do |c|
          c.tracing.instrument :mongo, describes: /#{host}/ do |mongo|
            mongo.service_name = primary_service
          end

          c.tracing.instrument :mongo, describes: /#{secondary_host}/ do |mongo|
            mongo.service_name = secondary_service
          end
        end
      end

      context 'primary client' do
        subject { client[collection].insert_one(name: 'FKA Twigs') }

        it 'produces spans with the correct service' do
          subject
          expect(spans).to have(1).items
          expect(spans.first.service).to eq(primary_service)
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end
      end

      context 'secondary client' do
        around do |example|
          without_warnings do
            # Reset before and after each example; don't allow global state to linger.
            Datadog.registry[:mongo].reset_configuration!
            example.run
            Datadog.registry[:mongo].reset_configuration!
            secondary_client.database.drop if drop_database?
            secondary_client.close
          end
        end

        subject { secondary_client[collection].insert_one(name: 'FKA Twigs') }

        it 'produces spans with the correct service' do
          subject
          expect(spans).to have(1).items
          expect(spans.first.service).to eq(secondary_service)
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { secondary_host }
        end
      end
    end

    context 'to disable the tracer' do
      before { tracer.enabled = false }

      it 'produces spans with the correct service' do
        client[collection].insert_one(name: 'FKA Twigs')
        expect(spans).to be_empty
      end
    end
  end

  # rubocop:disable Layout/LineLength
  describe 'tracing' do
    shared_examples_for 'a MongoDB trace' do
      it 'has basic properties' do
        expect(spans).to have(1).items
        expect(span.service).to eq('mongodb')
        expect(span.span_type).to eq('mongodb')
        expect(span.get_tag('db.system')).to eq('mongodb')
        expect(span.get_tag('mongodb.db')).to eq(database)
        collection_value = collection.is_a?(Numeric) ? collection : collection.to_s
        expect(span.get_tag('mongodb.collection')).to eq(collection_value)
        expect(span.get_tag('db.mongodb.collection')).to eq(collection_value)
        expect(span.get_tag('out.host')).to eq(host)
        expect(span.get_tag('out.port')).to eq(port)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('mongodb')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('command')
        expect(span.get_tag('span.kind')).to eq('client')
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::MongoDB::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::MongoDB::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'a peer service span' do
        let(:peer_hostname) { host }
      end

      it_behaves_like 'measured span for integration', false
      it_behaves_like 'environment service name', 'DD_TRACE_MONGO_SERVICE_NAME'
    end

    # Expects every value (except for keys) to be quantized.
    # - with: Defines expected placeholder value.
    # - except: Defines exceptions to quantization.
    #           Any Hash that intersects with this set
    #           will be expected to eq the intersection.
    #           e.g. except: { 'a' => 1 } will match { 'a' => 1, 'b' => '?' }
    RSpec::Matchers.define :be_quantized do
      match do |actual|
        actual_obj = actual.is_a?(String) ? JSON.parse(actual.gsub(/=>/, ':')) : actual

        options = {}.tap do |o|
          o[:with] = symbol unless symbol.nil?
          o[:except] = exceptions unless exceptions.nil?
        end

        quantized?(actual_obj, options)
      end

      def quantized?(object, options = {})
        with = options[:with] || '?'
        except = options[:except] || {}

        case object
        when String
          object == with.to_s
        when Array
          object.all? { |i| quantized?(i, options) }
        when Hash
          object.all? do |k, v|
            except.key?(k) ? v == except[k] : quantized?(v, options)
          end
        else
          true
        end
      end

      chain :with, :symbol
      chain :except, :exceptions
    end

    describe '#insert_one operation' do
      before { client[collection].insert_one(params) }

      context 'for a basic document' do
        let(:params) { { name: 'FKA Twigs' } }

        it_behaves_like 'a MongoDB trace'

        it 'has operation-specific properties' do
          if mongo_gem_version < Gem::Version.new('2.5')
            expect(span.resource).to eq("{\"operation\"=>:insert, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"documents\"=>[{:name=>\"?\"}], \"ordered\"=>\"?\"}")
          else
            expect(span.resource).to be_quantized.except('operation' => 'insert', 'database' => database, 'collection' => collection.to_s)
          end
          expect(span.get_tag('mongodb.rows')).to eq(1)
        end
      end

      context 'for a document with an array' do
        let(:params) { { name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'] } }
        let(:collection) { :people }

        it_behaves_like 'a MongoDB trace'

        it 'has operation-specific properties' do
          if mongo_gem_version < Gem::Version.new('2.5')
            expect(span.resource).to eq("{\"operation\"=>:insert, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"documents\"=>[{:name=>\"?\", :hobbies=>[\"?\"]}], \"ordered\"=>\"?\"}")
          else
            expect(span.resource).to be_quantized.except('operation' => 'insert', 'database' => database, 'collection' => collection.to_s)
          end
          expect(span.get_tag('mongodb.rows')).to eq(1)
        end
      end
    end

    describe '#insert_many operation' do
      before { client[collection].insert_many(params) }

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
          if mongo_gem_version < Gem::Version.new('2.5')
            expect(span.resource).to eq("{\"operation\"=>:insert, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"documents\"=>[{:name=>\"?\", :hobbies=>[\"?\"]}, \"?\"], \"ordered\"=>\"?\"}")
          else
            expect(span.resource).to be_quantized.except('operation' => 'insert', 'database' => database, 'collection' => collection.to_s)
          end
          expect(span.get_tag('mongodb.rows')).to eq(2)
        end
      end
    end

    describe '#find_all operation' do
      let(:collection) { :people }

      before do
        # Insert a document
        client[collection].insert_one(name: 'Steve', hobbies: ['hiking', 'tennis', 'fly fishing'])
        clear_traces!

        # Do #find_all operation
        client[collection].find.each do |document|
          # =>  Yields a BSON::Document.
        end
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>\"find\", \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"filter\"=>{}}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'find', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to be nil
      end
    end

    describe '#find operation' do
      let(:collection) { :people }

      before do
        # Insert a document
        client[collection].insert_one(name: 'Steve', hobbies: ['hiking'])
        clear_traces!

        # Do #find operation
        result = client[collection].find(name: 'Steve').first[:hobbies]
        expect(result).to eq(['hiking'])
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>\"find\", \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"filter\"=>{\"name\"=>\"?\"}}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'find', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to be nil
      end
    end

    describe '#update_one operation' do
      let(:collection) { :people }

      before do
        # Insert a document
        client[collection].insert_one(name: 'Sally', hobbies: ['skiing', 'stamp collecting'])
        clear_traces!

        # Do #update_one operation
        client[collection].update_one({ name: 'Sally' }, '$set' => { 'phone_number' => '555-555-5555' })
      end

      after do
        # Verify correctness of the operation
        expect(client[collection].find(name: 'Sally').first[:phone_number]).to eq('555-555-5555')
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>:update, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"updates\"=>[{\"q\"=>{\"name\"=>\"?\"}, \"u\"=>{\"$set\"=>{\"phone_number\"=>\"?\"}}, \"multi\"=>\"?\", \"upsert\"=>\"?\"}], \"ordered\"=>\"?\"}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'update', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to eq(1)
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

      before do
        # Insert documents
        client[collection].insert_many(documents)
        clear_traces!

        # Do #update_many operation
        client[collection].update_many({}, '$set' => { 'phone_number' => '555-555-5555' })
      end

      after do
        # Verify correctness of the operation
        documents.each do |d|
          expect(client[collection].find(name: d[:name]).first[:phone_number]).to eq('555-555-5555')
        end
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>:update, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"updates\"=>[{\"q\"=>{}, \"u\"=>{\"$set\"=>{\"phone_number\"=>\"?\"}}, \"multi\"=>\"?\", \"upsert\"=>\"?\"}], \"ordered\"=>\"?\"}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'update', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to eq(2)
      end
    end

    describe '#delete_one operation' do
      let(:collection) { :people }

      before do
        # Insert a document
        client[collection].insert_one(name: 'Sally', hobbies: ['skiing', 'stamp collecting'])
        clear_traces!

        # Do #delete_one operation
        client[collection].delete_one(name: 'Sally')
      end

      after do
        # Verify correctness of the operation
        expect(client[collection].find(name: 'Sally').count).to eq(0)
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>:delete, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"deletes\"=>[{\"q\"=>{\"name\"=>\"?\"}, \"limit\"=>\"?\"}], \"ordered\"=>\"?\"}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'delete', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to eq(1)
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

      before do
        # Insert documents
        client[collection].insert_many(documents)
        clear_traces!

        # Do #delete_many operation
        client[collection].delete_many(name: /$S*/)
      end

      after do
        # Verify correctness of the operation
        documents.each do |d|
          expect(client[collection].find(name: d[:name]).count).to eq(0)
        end
      end

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>:delete, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\", \"deletes\"=>[{\"q\"=>{\"name\"=>\"?\"}, \"limit\"=>\"?\"}], \"ordered\"=>\"?\"}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'delete', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to eq(2)
      end
    end

    describe '#drop operation' do
      let(:collection) { 1 } # Because drop operation doesn't have a collection

      before { client.database.drop }

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>:dropDatabase, \"database\"=>\"#{database}\", \"collection\"=>1}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'dropDatabase', 'database' => database, 'collection' => 1)
        end
        expect(span.get_tag('mongodb.rows')).to be nil
      end
    end

    describe 'a failed query' do
      before { client[:artists].drop }

      it_behaves_like 'a MongoDB trace'

      it 'has operation-specific properties' do
        if mongo_gem_version < Gem::Version.new('2.5')
          expect(span.resource).to eq("{\"operation\"=>:drop, \"database\"=>\"#{database}\", \"collection\"=>\"#{collection}\"}")
        else
          expect(span.resource).to be_quantized.except('operation' => 'drop', 'database' => database, 'collection' => collection.to_s)
        end
        expect(span.get_tag('mongodb.rows')).to be nil
        expect(span.status).to eq(1)
        expect(span.get_tag('error.message')).to eq('ns not found (26)')
      end

      context 'that triggers #failed before #started' do
        subject(:failed_event) { subscriber.failed(event) }

        let(:event) { instance_double(Mongo::Monitoring::Event::CommandFailed, request_id: double('request_id')) }
        let(:subscriber) { Datadog::Tracing::Contrib::MongoDB::MongoCommandSubscriber.new }

        # Clear the thread variable out, as if #started has never run.
        before { Thread.current[:datadog_mongo_span] = nil }

        it { expect { failed_event }.to_not raise_error }
      end
    end

    describe 'with LDAP/SASL authentication' do
      let(:client_options) do
        super().merge(auth_mech: :plain, user: 'plain_user', password: 'plain_pass')
      end

      context 'which fails' do
        let(:insert_span) { spans.first }
        let(:auth_span) { spans.last }
        let(:drop_database?) { false }

        before do
          begin
            # Insert a document
            client[collection].insert_one(name: 'Steve', hobbies: ['hiking'])
          rescue Mongo::Auth::Unauthorized
            # Expect this to create an unauthorized error
            nil
          end
        end

        it 'produces spans for command and authentication' do
          # In versions of Mongo < 2.5...
          # With LDAP/SASL, Mongo will run a "saslStart" command
          # after the original command starts but before it finishes.
          # Thus we should expect it to create an authentication span
          # that is a child of the original command span.
          if mongo_gem_version < Gem::Version.new('2.5')
            expect(spans).to have(2).items
          else
            expect(spans).to have(1).items
          end

          if mongo_gem_version < Gem::Version.new('2.5')
            expect(insert_span.name).to eq('mongo.cmd')
            expect(insert_span.resource).to match(/"operation"\s*=>\s*:insert/)
            expect(insert_span.status).to eq(1)
            expect(insert_span.get_tag('error.type')).to eq('Mongo::Monitoring::Event::CommandFailed')
            expect(insert_span.get_tag('error.message')).to match(/.*is not authorized to access.*/)
            expect(insert_span.get_tag('db.system')).to eq('mongodb')
          end

          expect(auth_span.name).to eq('mongo.cmd')
          expect(auth_span.resource).to match(/"operation"\s*=>\s*[:"]saslStart/)
          expect(auth_span.status).to eq(1)
          expect(auth_span.get_tag('error.type')).to eq('Mongo::Monitoring::Event::CommandFailed')
          expect(auth_span.get_tag('error.message')).to eq('Unsupported mechanism PLAIN (2)')
          expect(auth_span.get_tag('db.system')).to eq('mongodb')
        end
      end
    end
  end
end
