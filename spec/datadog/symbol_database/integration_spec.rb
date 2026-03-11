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
        uploader = double('uploader')
        allow(uploader).to receive(:upload_scopes) { |scopes| uploaded_scopes = scopes }

        # Create scope context
        context = Datadog::SymbolDatabase::ScopeContext.new(uploader)

        # Extract symbols
        scope = Datadog::SymbolDatabase::Extractor.extract(IntegrationTestModule::IntegrationTestClass)

        # Should have extracted the class
        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('CLASS')
        expect(scope.name).to eq('IntegrationTestModule::IntegrationTestClass')

        # Should have method scopes
        method_names = scope.scopes.map(&:name)
        expect(method_names).to include('test_method')
        expect(method_names).to include('self.class_method')

        # Should have symbols (class variable)
        symbol_names = scope.symbols.map(&:name)
        expect(symbol_names).to include('@@class_var')

        # Should have method parameters
        test_method_scope = scope.scopes.find { |s| s.name == 'test_method' }
        param_names = test_method_scope.symbols.map(&:name)
        expect(param_names).to include('arg1')
        expect(param_names).to include('arg2')

        # Add to context (should batch)
        context.add_scope(scope)
        expect(context.size).to eq(1)

        # Flush (should upload)
        context.flush

        # Verify upload was called
        expect(uploaded_scopes).not_to be_nil
        expect(uploaded_scopes.size).to eq(1)
        expect(uploaded_scopes.first.name).to eq('IntegrationTestModule::IntegrationTestClass')

        # Verify JSON serialization works
        json = uploaded_scopes.first.to_json
        parsed = JSON.parse(json)
        expect(parsed['scope_type']).to eq('CLASS')
        expect(parsed['scopes']).to be_an(Array)
        expect(parsed['symbols']).to be_an(Array)
      ensure
        # Cleanup
        Object.send(:remove_const, :IntegrationTestModule) if defined?(IntegrationTestModule)
      end
    end
  end
end
