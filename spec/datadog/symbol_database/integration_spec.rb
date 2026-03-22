# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/extractor'
require 'datadog/symbol_database/scope_context'
require 'datadog/symbol_database/uploader'
require 'fileutils'

RSpec.describe 'Symbol Database Integration' do
  # End-to-end integration test
  it 'extracts, batches, and uploads symbols from user code' do
    # Setup: Create test class in isolated temp directory
    test_file = nil
    Dir.mktmpdir('symbol_db_integration') do |dir|
      test_file = File.join(dir, "integration_test_#{Time.now.to_i}.rb")
      File.write(test_file, <<~RUBY)
        module IntegrationTestModule
          CONSTANT = 42

          # Module method ensures find_source_file can locate this module's source file
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

      begin
        # Load the test code
        load test_file

        # Mock uploader to capture upload
        uploaded_scopes = nil
        uploader = instance_double(Datadog::SymbolDatabase::Uploader)
        allow(uploader).to receive(:upload_scopes) { |scopes| uploaded_scopes = scopes }

        # Create scope context
        context = Datadog::SymbolDatabase::ScopeContext.new(uploader)

        # Namespaced classes are also extractable as standalone root FILE scopes,
        # ensuring they appear in search even if the parent namespace can't be extracted.
        nested_file_scope = Datadog::SymbolDatabase::Extractor.extract(IntegrationTestModule::IntegrationTestClass)
        expect(nested_file_scope).not_to be_nil
        expect(nested_file_scope.scope_type).to eq('FILE')
        expect(nested_file_scope.name).to eq(nested_file_scope.source_file)

        # Extract the parent MODULE — wrapped in a FILE scope
        file_scope = Datadog::SymbolDatabase::Extractor.extract(IntegrationTestModule)
        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.language_specifics[:file_hash]).not_to be_nil

        module_scope = file_scope.scopes.first
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('IntegrationTestModule')

        # The nested CLASS is inside the MODULE's scopes
        class_scope = module_scope.scopes.find { |s| s.scope_type == 'CLASS' }
        expect(class_scope).not_to be_nil
        expect(class_scope.name).to eq('IntegrationTestModule::IntegrationTestClass')

        # Should have instance method scopes inside the CLASS
        # Class methods (self.foo) are not extracted by default — Ruby DI instruments
        # via prepend on the instance method chain, not the singleton class.
        method_names = class_scope.scopes.map(&:name)
        expect(method_names).to include('test_method')
        expect(method_names).not_to include('self.class_method')

        # Should have symbols (class variable) inside the CLASS
        symbol_names = class_scope.symbols.map(&:name)
        expect(symbol_names).to include('@@class_var')

        # Should have method parameters
        test_method_scope = class_scope.scopes.find { |s| s.name == 'test_method' }
        param_names = test_method_scope.symbols.map(&:name)
        expect(param_names).to include('arg1')
        expect(param_names).to include('arg2')

        # Add to context (should batch)
        context.add_scope(file_scope)
        expect(context.size).to eq(1)

        # Flush (should upload)
        context.flush

        # Verify upload was called with the FILE scope
        expect(uploaded_scopes).not_to be_nil
        expect(uploaded_scopes.size).to eq(1)
        expect(uploaded_scopes.first.name).to eq(test_file)
        expect(uploaded_scopes.first.scope_type).to eq('FILE')

        # Verify JSON serialization produces valid root-level FILE scope
        json = uploaded_scopes.first.to_json
        parsed = JSON.parse(json)
        expect(parsed['scope_type']).to eq('FILE')
        expect(parsed['scopes']).to be_an(Array)
      ensure
        # Cleanup
        Object.send(:remove_const, :IntegrationTestModule) if defined?(IntegrationTestModule)
      end
    end
  end
end
