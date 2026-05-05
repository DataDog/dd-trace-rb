# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/remote'
require 'datadog/symbol_database/logger'
require 'fileutils'

# Integration test for the RC → Component → Extractor → ScopeBatcher → Uploader flow.
# Mocks at the transport boundary (Transport::HTTP.build) to capture what would be sent
# to the agent, without multipart parsing or real HTTP.
RSpec.describe 'Symbol Database Remote Config Integration' do
  let(:raw_logger) { instance_double(Logger, debug: nil) }
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.symbol_database.internal.force_upload = false
      s.remote.enabled = true
      s.service = 'rc-integration-test'
      s.env = 'test'
      s.version = '1.0.0'
      s.agent.host = 'localhost'
      s.agent.port = 8126
    end
  end
  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end
  let(:symdb_logger) { Datadog::SymbolDatabase::Logger.new(settings, raw_logger) }
  let(:mock_transport) { instance_double(Datadog::SymbolDatabase::Transport::Transport) }
  let(:mock_response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, code: 200, internal_error?: false) }

  let(:captured_forms) { [] }

  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:build).and_return(mock_transport)
    allow(mock_transport).to receive(:send_symdb_payload) do |form|
      captured_forms << form
      mock_response
    end

    # Reset cross-test class-level state and shorten the debounce window so
    # tests don't wait the production 5 seconds.
    Datadog::SymbolDatabase::Component.reset_uploaded_this_process_for_tests!
    stub_const('Datadog::SymbolDatabase::Component::EXTRACT_DEBOUNCE_INTERVAL', 0.05)
  end

  # Load test code in a temp dir (not /spec/) so it passes user_code_path? filter
  around do |example|
    Dir.mktmpdir('rc_integration') do |dir|
      test_file = File.join(dir, "rc_test_#{Time.now.to_i}_#{rand(10000)}.rb")
      File.write(test_file, <<~RUBY)
        module RCIntegrationTestModule
          class RCIntegrationTestClass
            CONSTANT = 42
            @@class_var = 'test'

            def instance_method_one(arg1, arg2)
              arg1 + arg2
            end
          end
        end
      RUBY

      test_file = File.realpath(test_file)
      load test_file

      begin
        example.run
      ensure
        Object.send(:remove_const, :RCIntegrationTestModule) if defined?(RCIntegrationTestModule)
      end
    end
  end

  describe 'Component.start_upload triggers full extraction and upload' do
    it 'extracts user code and sends payload via transport' do
      component = Datadog::SymbolDatabase::Component.build(
        settings,
        agent_settings,
        symdb_logger
      )
      expect(component).not_to be_nil

      GC.start
      component.start_upload
      component.wait_for_idle(timeout: 30)

      # Transport should have been called with a multipart form
      expect(captured_forms).not_to be_empty

      form = captured_forms.last
      expect(form).to have_key('event')
      expect(form).to have_key('file')

      # Verify event metadata
      event_io = form['event'].instance_variable_get(:@io)
      event_json = JSON.parse(event_io.string)
      expect(event_json['service']).to eq('rc-integration-test')
      expect(event_json['type']).to eq('symdb')
      expect(event_json).to have_key('runtimeId')

      # Verify file content (decompress gzip, parse JSON)
      file_io = form['file'].instance_variable_get(:@io)
      json_data = Zlib.gunzip(file_io.string)
      payload = JSON.parse(json_data)

      expect(payload['service']).to eq('rc-integration-test')
      expect(payload['env']).to eq('test')
      expect(payload['version']).to eq('1.0.0')
      expect(payload['scopes']).to be_an(Array)
      expect(payload['scopes']).not_to be_empty

      # Find our test class in the scopes (nested under FILE → MODULE → CLASS)
      file_scope = payload['scopes'].find do |s|
        s['scope_type'] == 'FILE' && (s['scopes'] || []).any? { |c| c['name'] == 'RCIntegrationTestModule' }
      end
      expect(file_scope).not_to be_nil

      module_scope = file_scope['scopes'].find { |s| s['name'] == 'RCIntegrationTestModule' }
      expect(module_scope).not_to be_nil
      expect(module_scope['scope_type']).to eq('MODULE')

      class_scope = module_scope['scopes'].find { |s| s['name'] == 'RCIntegrationTestModule::RCIntegrationTestClass' }
      expect(class_scope).not_to be_nil
      expect(class_scope['scope_type']).to eq('CLASS')

      method_names = class_scope['scopes']
        .select { |s| s['scope_type'] == 'METHOD' }
        .map { |s| s['name'] }
      expect(method_names).to include('instance_method_one')

      # No Datadog:: internal classes should be in the payload
      all_names = payload['scopes'].flat_map { |s| collect_scope_names(s) }
      datadog_names = all_names.select { |n| n&.start_with?('Datadog::') }
      expect(datadog_names).to be_empty

      component.shutdown!
    end
  end

  describe 'Remote.process_change drives Component' do
    it 'starts upload when RC sends upload_symbols: true' do
      component = Datadog::SymbolDatabase::Component.build(
        settings,
        agent_settings,
        symdb_logger
      )

      # Simulate RC change: insert with upload_symbols: true
      content = instance_double('Datadog::Core::Remote::Configuration::Content', data: JSON.generate('upload_symbols' => true))
      allow(content).to receive(:applied)
      change = instance_double('Datadog::Core::Remote::Configuration::Repository::Change::Inserted', type: :insert, content: content)

      GC.start
      Datadog::SymbolDatabase::Remote.send(:process_change, component, change)
      component.wait_for_idle(timeout: 30)

      expect(captured_forms).not_to be_empty
      expect(content).to have_received(:applied)

      component.shutdown!
    end

    it 'does not upload when RC sends upload_symbols: false' do
      component = Datadog::SymbolDatabase::Component.build(
        settings,
        agent_settings,
        symdb_logger
      )

      content = instance_double('Datadog::Core::Remote::Configuration::Content', data: JSON.generate('upload_symbols' => false))
      allow(content).to receive(:applied)
      change = instance_double('Datadog::Core::Remote::Configuration::Repository::Change::Inserted', type: :insert, content: content)

      Datadog::SymbolDatabase::Remote.send(:process_change, component, change)

      expect(captured_forms).to be_empty
      expect(content).to have_received(:applied)

      component.shutdown!
    end

    it 'stops upload on RC delete' do
      component = Datadog::SymbolDatabase::Component.build(
        settings,
        agent_settings,
        symdb_logger
      )

      # First enable
      content = instance_double('Datadog::Core::Remote::Configuration::Content', data: JSON.generate('upload_symbols' => true))
      allow(content).to receive(:applied)
      insert_change = instance_double('Datadog::Core::Remote::Configuration::Repository::Change::Inserted', type: :insert, content: content)

      GC.start
      Datadog::SymbolDatabase::Remote.send(:process_change, component, insert_change)
      component.wait_for_idle(timeout: 30)
      expect(captured_forms).not_to be_empty

      # Then delete
      previous = instance_double('Datadog::Core::Remote::Configuration::Content')
      allow(previous).to receive(:applied)
      delete_change = instance_double('Datadog::Core::Remote::Configuration::Repository::Change::Deleted', type: :delete, previous: previous)

      Datadog::SymbolDatabase::Remote.send(:process_change, component, delete_change)
      expect(previous).to have_received(:applied)

      component.shutdown!
    end
  end

  describe 'class-level dedup prevents re-upload' do
    it 'does not extract again after a successful upload in this process' do
      component = Datadog::SymbolDatabase::Component.build(
        settings,
        agent_settings,
        symdb_logger
      )

      GC.start
      component.start_upload
      component.wait_for_idle(timeout: 30)
      upload_count_after_first = captured_forms.size

      # Second call should be a no-op (uploaded_this_process? is true).
      component.stop_upload
      component.start_upload
      sleep 0.2
      expect(captured_forms.size).to eq(upload_count_after_first)

      component.shutdown!
    end
  end

  private

  # Recursively collect all scope names from a nested scope hash
  def collect_scope_names(scope)
    names = [scope['name']]
    (scope['scopes'] || []).each do |child|
      names.concat(collect_scope_names(child))
    end
    names
  end
end
