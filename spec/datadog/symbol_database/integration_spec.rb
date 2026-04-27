# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/extractor'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/uploader'
require 'fileutils'

RSpec.describe 'Symbol Database Integration' do
  # End-to-end integration test using the production extract_all path
  it 'extracts, batches, and uploads symbols from user code' do
    Dir.mktmpdir('symbol_db_integration') do |dir|
      test_file = File.join(dir, "integration_test_#{Time.now.to_i}.rb")
      File.write(test_file, <<~RUBY)
        module IntegrationTestModule
          CONSTANT = 42

          def self.module_info
            "integration test module"
          end

          class IntegrationTestClass
            @@class_var = "test"

            def test_method(arg1, arg2)
              arg1 + arg2
            end

            def self.class_method
              "result"
            end
          end
        end
      RUBY

      # Resolve symlinks (macOS /var → /private/var) so path matches source_location
      test_file = File.realpath(test_file)

      begin
        load test_file

        # Mock uploader to capture uploads
        uploaded_scopes = []
        uploader = instance_double(Datadog::SymbolDatabase::Uploader)
        allow(uploader).to receive(:upload_scopes) { |scopes| uploaded_scopes.concat(scopes) }

        settings = double('settings')
        symdb_settings = double('symbol_database', internal: double('internal'))
        allow(settings).to receive(:symbol_database).and_return(symdb_settings)
        logger = instance_double(Logger, debug: nil)

        context = Datadog::SymbolDatabase::ScopeBatcher.new(uploader, logger: logger)
        extractor = Datadog::SymbolDatabase::Extractor.new(logger: logger, settings: settings)

        # Use extract_all — the production path
        # GC.start cleans up stale modules from other tests in ObjectSpace
        GC.start
        file_scopes = extractor.extract_all

        # Find our test file's scope by content (not path — ObjectSpace may have stale modules)
        file_scope = file_scopes.find { |s| s.scope_type == 'FILE' && s.scopes.any? { |c| c.name == 'IntegrationTestModule' } }
        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.language_specifics[:file_hash]).to match(/\A[0-9a-f]{40}\z/)

        # MODULE nested under FILE via FQN splitting
        module_scope = file_scope.scopes.find { |s| s.name == 'IntegrationTestModule' }
        expect(module_scope).not_to be_nil
        expect(module_scope.scope_type).to eq('MODULE')

        # CLASS nested under MODULE via FQN splitting (FQN name)
        class_scope = module_scope.scopes.find { |s| s.name == 'IntegrationTestModule::IntegrationTestClass' }
        expect(class_scope).not_to be_nil
        expect(class_scope.scope_type).to eq('CLASS')

        # Instance method — class methods not extracted by default
        method_names = class_scope.scopes.select { |s| s.scope_type == 'METHOD' }.map(&:name)
        expect(method_names).to include('test_method')

        # Class variable symbol
        symbol_names = class_scope.symbols.map(&:name)
        expect(symbol_names).to include('@@class_var')

        # Method parameters (arg1 + arg2, no self)
        test_method_scope = class_scope.scopes.find { |s| s.name == 'test_method' }
        param_names = test_method_scope.symbols.map(&:name)
        expect(param_names).to include('arg1', 'arg2')
        expect(param_names).not_to include('self')

        # Injectable lines on METHOD scope (production path)
        expect(test_method_scope.injectible_lines?).to eq(true)
        expect(test_method_scope.injectible_lines).to be_an(Array)
        expect(test_method_scope.injectible_lines).not_to be_empty
        test_method_scope.injectible_lines.each do |range|
          expect(range[:start]).to be <= range[:end]
          expect(range[:start]).to be >= test_method_scope.start_line
          expect(range[:end]).to be <= test_method_scope.end_line
        end
        expect(test_method_scope.end_line).to be > test_method_scope.start_line

        # Batch and upload
        context.add_scope(file_scope)
        context.flush

        expect(uploaded_scopes).not_to be_empty
        uploaded_file = uploaded_scopes.first
        expect(uploaded_file.scope_type).to eq('FILE')

        # JSON round-trip
        json = uploaded_file.to_json
        parsed = JSON.parse(json)
        expect(parsed['scope_type']).to eq('FILE')
        expect(parsed['scopes']).to be_an(Array)

        # Injectable lines survive JSON round-trip
        parsed_method = parsed['scopes']
          .flat_map { |s| s['scopes'] || [] }
          .flat_map { |s| s['scopes'] || [] }
          .find { |s| s['name'] == 'test_method' }
        expect(parsed_method).not_to be_nil
        expect(parsed_method['has_injectible_lines']).to eq(true)
        expect(parsed_method['injectible_lines']).to be_an(Array)
        expect(parsed_method['injectible_lines']).not_to be_empty
      ensure
        Object.send(:remove_const, :IntegrationTestModule) if defined?(IntegrationTestModule)
      end
    end
  end

  describe 'wire format' do
    it 'builds multipart form with event.json and gzipped symbols file' do
      config = double('config', service: 'test-service', env: 'test', version: '1.0')
      agent_settings = instance_double(
        Datadog::Core::Configuration::AgentSettings,
        hostname: 'localhost', port: 8126, timeout_seconds: 30, ssl: false
      )
      logger = instance_double(Logger, debug: nil)

      transport = instance_double(Datadog::SymbolDatabase::Transport::Transport)
      allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:build).and_return(transport)

      uploader = Datadog::SymbolDatabase::Uploader.new(config, agent_settings, logger: logger)

      scope = Datadog::SymbolDatabase::Scope.new(
        scope_type: 'FILE',
        name: '/app/test.rb',
        source_file: '/app/test.rb',
        start_line: 1,
        end_line: 10,
        scopes: []
      )

      captured_form = nil
      allow(transport).to receive(:send_symdb_payload) do |form|
        captured_form = form
        instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: true, code: 200, internal_error?: false)
      end

      uploader.upload_scopes([scope])

      expect(captured_form).not_to be_nil
      expect(captured_form['event']).to be_a(Datadog::Core::Vendor::Multipart::Post::UploadIO)
      expect(captured_form['file']).to be_a(Datadog::Core::Vendor::Multipart::Post::UploadIO)

      # Verify event.json content
      event_json = JSON.parse(captured_form['event'].io.string)
      expect(event_json['ddsource']).to eq('ruby')
      expect(event_json['service']).to eq('test-service')
      expect(event_json['runtimeId']).not_to be_nil

      # Verify file is gzip-compressed JSON with correct structure
      compressed = captured_form['file'].io.string
      decompressed = Zlib::GzipReader.new(StringIO.new(compressed)).read
      payload = JSON.parse(decompressed)
      expect(payload).to be_a(Hash)
      expect(payload['language']).to eq('ruby')
      expect(payload['service']).to eq('test-service')
      expect(payload['env']).to eq('test')
      expect(payload['version']).to eq('1.0')
      expect(payload['scopes']).to be_an(Array)
      expect(payload['scopes'].first['scope_type']).to eq('FILE')
    end
  end
end
