# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/extractor'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/uploader'
require 'datadog/core/utils/only_once'

RSpec.describe Datadog::SymbolDatabase::Component do
  # Use a real Settings instance — Settings uses dynamic DSL methods (via
  # Core::Configuration::Options) that instance_double can't verify.
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.symbol_database.internal.force_upload = false
      s.remote.enabled = true
      s.service = 'test-service'
      s.env = 'test'
      s.version = '1.0'
    end
  end

  let(:agent_settings) do
    instance_double(
      Datadog::Core::Configuration::AgentSettings,
      hostname: 'localhost',
      port: 8126,
      timeout_seconds: 30,
      ssl: false,
    )
  end

  let(:raw_logger) { instance_double(Logger, debug: nil) }
  let(:logger) { Datadog::SymbolDatabase::Logger.new(settings, raw_logger) }
  # Reset the class-level OnlyOnce guard between tests
  before do
    described_class::FORCE_UPLOAD_ONCE.send(:reset_ran_once_state_for_tests)
  end

  # Stub Uploader and ScopeBatcher to avoid real HTTP calls
  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:build).and_return(
      instance_double(Datadog::SymbolDatabase::Transport::Transport)
    )
    allow(Datadog::SymbolDatabase::ScopeBatcher).to receive(:new).and_return(
      instance_double(Datadog::SymbolDatabase::ScopeBatcher, shutdown: nil, add_scope: nil, flush: nil, reset: nil)
    )
  end

  describe '.environment_supported?', :symdb_supported_platforms do
    it 'returns true on MRI Ruby 2.6+' do
      stub_const('RUBY_ENGINE', 'ruby')
      stub_const('RUBY_VERSION', '3.2.0')
      expect(described_class.send(:environment_supported?, logger)).to be true
    end

    it 'returns false and logs on JRuby' do
      stub_const('RUBY_ENGINE', 'jruby')
      expect(raw_logger).to receive(:debug) { |&block| expect(block.call).to match(/not supported on jruby/) }

      expect(described_class.send(:environment_supported?, logger)).to be false
    end

    it 'returns false and logs on Ruby < 2.6' do
      stub_const('RUBY_ENGINE', 'ruby')
      stub_const('RUBY_VERSION', '2.5.9')
      expect(raw_logger).to receive(:debug) { |&block| expect(block.call).to match(/requires Ruby 2\.6\+/) }

      expect(described_class.send(:environment_supported?, logger)).to be false
    end
  end

  describe '.build' do
    it 'returns nil when symbol_database is not enabled' do
      allow(settings.symbol_database).to receive(:enabled).and_return(false)

      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_nil
    end

    it 'returns nil on unsupported Ruby engine (JRuby)', :symdb_supported_platforms do
      stub_const('RUBY_ENGINE', 'jruby')
      allow(logger).to receive(:debug)

      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_nil
    end

    it 'returns nil on Ruby < 2.6', :symdb_supported_platforms do
      stub_const('RUBY_VERSION', '2.5.9')
      allow(logger).to receive(:debug)

      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_nil
    end

    it 'returns nil when remote is not enabled and force_upload is false' do
      allow(settings.remote).to receive(:enabled).and_return(false)
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(false)

      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_nil
    end

    it 'returns a Component when enabled and remote is enabled' do
      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_a(described_class)
    end

    it 'returns a Component when DI is disabled (SymDB is independent of DI)' do
      allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(false)

      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_a(described_class)
    end

    it 'returns a Component when force_upload is true even without remote' do
      allow(settings.remote).to receive(:enabled).and_return(false)
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)

      result = described_class.build(settings, agent_settings, logger)
      expect(result).to be_a(described_class)
    end

    context 'with force_upload enabled' do
      before do
        allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
      end

      it 'calls schedule_deferred_upload instead of start_upload directly' do
        expect_any_instance_of(described_class).to receive(:schedule_deferred_upload)
        expect_any_instance_of(described_class).not_to receive(:extract_and_upload)

        described_class.build(settings, agent_settings, logger)
      end
    end

    context 'without force_upload' do
      it 'does not call schedule_deferred_upload' do
        expect_any_instance_of(described_class).not_to receive(:schedule_deferred_upload)

        described_class.build(settings, agent_settings, logger)
      end
    end
  end

  describe '#schedule_deferred_upload' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    context 'without Rails (non-Rails context)' do
      before do
        hide_const('ActiveSupport')
        hide_const('Rails::Railtie')
      end

      it 'calls start_upload immediately' do
        expect(component).to receive(:start_upload)

        component.schedule_deferred_upload
      end

      it 'only triggers extraction once across multiple calls (OnlyOnce guard)' do
        expect(component).to receive(:start_upload).once

        component.schedule_deferred_upload
        component.schedule_deferred_upload
        component.schedule_deferred_upload
      end

      it 'only triggers extraction once across multiple component instances' do
        component2 = described_class.new(settings, agent_settings, logger)

        expect(component).to receive(:start_upload).once
        expect(component2).not_to receive(:start_upload)

        component.schedule_deferred_upload
        component2.schedule_deferred_upload
      end
    end

    context 'with Rails detected' do
      let(:after_init_callbacks) { [] }

      before do
        active_support_mod = Module.new do
          def self.on_load(_name, &block)
          end
        end
        stub_const('ActiveSupport', active_support_mod)
        stub_const('Rails::Railtie', Class.new)

        allow(::ActiveSupport).to receive(:on_load).with(:after_initialize) do |&block|
          after_init_callbacks << block
        end
      end

      it 'defers extraction to ActiveSupport.on_load(:after_initialize)' do
        expect(component).not_to receive(:start_upload)

        component.schedule_deferred_upload

        expect(after_init_callbacks.size).to eq(1)
      end

      it 'triggers start_upload on current component when callback fires' do
        component.schedule_deferred_upload

        # Callback looks up current component via Datadog.components
        components = instance_double(Datadog::Core::Configuration::Components, symbol_database: component)
        allow(Datadog).to receive(:components).and_return(components)

        expect(component).to receive(:start_upload)

        after_init_callbacks.each(&:call)
      end

      it 'uses current component at callback-fire time, not build-time component' do
        component.schedule_deferred_upload
        component.shutdown!

        # Simulate reconfiguration: component2 is now current
        component2 = described_class.new(settings, agent_settings, logger)
        components = instance_double(Datadog::Core::Configuration::Components, symbol_database: component2)
        allow(Datadog).to receive(:components).and_return(components)

        expect(component).not_to receive(:start_upload)
        expect(component2).to receive(:start_upload)

        after_init_callbacks.each(&:call)
      end

      it 'only registers the after_initialize callback once across reconfigurations' do
        component2 = described_class.new(settings, agent_settings, logger)

        component.schedule_deferred_upload
        component2.schedule_deferred_upload

        expect(after_init_callbacks.size).to eq(1)
      end
    end
  end

  describe '#start_upload' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    it 'triggers extract_and_upload on first call' do
      expect(component).to receive(:extract_and_upload)

      component.start_upload
    end

    it 'does not trigger extract_and_upload on subsequent calls (enabled guard)' do
      expect(component).to receive(:extract_and_upload).once

      component.start_upload
      component.start_upload
    end

    it 'does not trigger extract_and_upload if shutdown' do
      component.shutdown!

      expect(component).not_to receive(:extract_and_upload)

      component.start_upload
    end
  end

  describe 'diagnostic accessors' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    describe '#enabled' do
      it 'is false before start_upload' do
        expect(component.enabled).to be false
      end

      it 'is true after start_upload' do
        allow(component).to receive(:extract_and_upload)
        component.start_upload
        expect(component.enabled).to be true
      end

      it 'is false after stop_upload' do
        allow(component).to receive(:extract_and_upload)
        component.start_upload
        component.stop_upload
        expect(component.enabled).to be false
      end
    end

    describe '#last_upload_time' do
      it 'is nil before start_upload' do
        expect(component.last_upload_time).to be_nil
      end

      it 'is a Time after start_upload' do
        allow(component).to receive(:extract_and_upload)
        component.start_upload
        expect(component.last_upload_time).to be_a(Time)
      end
    end

    describe '#upload_in_progress' do
      it 'is false before any upload' do
        expect(component.upload_in_progress).to be false
      end

      it 'is true during extract_and_upload and false after' do
        in_progress_during_extraction = nil
        extractor = component.instance_variable_get(:@extractor)
        allow(extractor).to receive(:extract_all) do
          in_progress_during_extraction = component.upload_in_progress
          []
        end

        component.start_upload
        expect(in_progress_during_extraction).to be true
        expect(component.upload_in_progress).to be false
      end
    end
  end

  describe '#shutdown!' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    it 'sets shutdown flag' do
      expect(component.shutdown?).to be false

      component.shutdown!

      expect(component.shutdown?).to be true
    end

    it 'prevents subsequent start_upload from running' do
      component.shutdown!

      expect(component).not_to receive(:extract_and_upload)

      component.start_upload
    end
  end

  describe 'reconfiguration scenario' do
    before do
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
      hide_const('ActiveSupport')
      hide_const('Rails::Railtie')
    end

    it 'only performs one extraction across multiple Component rebuilds' do
      extraction_count = 0
      allow_any_instance_of(described_class).to receive(:extract_and_upload) { extraction_count += 1 }

      component1 = described_class.build(settings, agent_settings, logger)
      described_class.build(settings, agent_settings, logger)
      component1.shutdown!

      expect(extraction_count).to eq(1)
    end
  end

  # === Tests ported from Java SymDBEnablementTest ===

  describe 'enable/disable upload (ported from Java SymDBEnablementTest.enableDisableSymDBThroughRC)' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    it 'starts upload and then stops it' do
      expect(component).to receive(:extract_and_upload).once

      component.start_upload
      expect(component.enabled).to be true

      component.stop_upload
      expect(component.enabled).to be false
    end

    it 'does not extract again after stop and re-start (already enabled guard)' do
      expect(component).to receive(:extract_and_upload).once

      component.start_upload
      component.stop_upload
      # Second start_upload should be blocked by recently_uploaded? cooldown
      component.start_upload

      # Only one extraction expected
    end
  end

  describe 'config removal (ported from Java SymDBEnablementTest.removeSymDBConfig)' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    it 'shutdown prevents any future uploads' do
      allow(component).to receive(:extract_and_upload)

      component.start_upload
      component.shutdown!

      # After shutdown, start_upload should be a no-op
      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
    end
  end

  describe 'filtering behavior (ported from Java SymDBEnablementTest.noIncludesFilterOutDatadogClass)' do
    let(:component) do
      described_class.new(settings, agent_settings, logger)
    end

    it 'extract_and_upload filters out Datadog internal classes' do
      uploaded_scopes = []
      mock_scope_batcher = instance_double(Datadog::SymbolDatabase::ScopeBatcher)
      allow(mock_scope_batcher).to receive(:add_scope) { |scope| uploaded_scopes << scope }
      allow(mock_scope_batcher).to receive(:flush)
      allow(mock_scope_batcher).to receive(:shutdown)
      component.instance_variable_set(:@scope_batcher, mock_scope_batcher)

      component.send(:extract_and_upload)

      # No Datadog:: scopes should have been added
      datadog_scopes = uploaded_scopes.select { |s| s.name&.start_with?('Datadog::') }
      expect(datadog_scopes).to be_empty
    end
  end
end
