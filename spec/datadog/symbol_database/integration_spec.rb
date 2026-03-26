# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/extractor'
require 'datadog/symbol_database/scope_context'
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
        symdb_settings = double('symbol_database', internal: double('internal', upload_class_methods: false))
        allow(settings).to receive(:symbol_database).and_return(symdb_settings)
        logger = instance_double(Logger, debug: nil)

        context = Datadog::SymbolDatabase::ScopeContext.new(uploader, logger: logger)
        extractor = Datadog::SymbolDatabase::Extractor.new(logger: logger, settings: settings, telemetry: nil)

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

        # CLASS nested under MODULE via FQN splitting (short name)
        class_scope = module_scope.scopes.find { |s| s.name == 'IntegrationTestClass' }
        expect(class_scope).not_to be_nil
        expect(class_scope.scope_type).to eq('CLASS')

        # Instance method — class methods not extracted by default
        method_names = class_scope.scopes.select { |s| s.scope_type == 'METHOD' }.map(&:name)
        expect(method_names).to include('test_method')

        # Class variable symbol
        symbol_names = class_scope.symbols.map(&:name)
        expect(symbol_names).to include('@@class_var')

        # Method parameters (self + arg1 + arg2)
        test_method_scope = class_scope.scopes.find { |s| s.name == 'test_method' }
        param_names = test_method_scope.symbols.map(&:name)
        expect(param_names).to include('self', 'arg1', 'arg2')

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
      ensure
        Object.send(:remove_const, :IntegrationTestModule) if defined?(IntegrationTestModule)
      end
    end
  end
end
