# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/extractor'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/uploader'

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

  # Stub Uploader and ScopeBatcher to avoid real HTTP calls.
  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:symbols).and_return(
      instance_double(Datadog::SymbolDatabase::Transport::Symbols::Transport)
    )
    allow(Datadog::SymbolDatabase::ScopeBatcher).to receive(:new).and_return(
      instance_double(Datadog::SymbolDatabase::ScopeBatcher, shutdown: nil, add_scope: nil, flush: nil, reset: nil)
    )
  end

  # Make the debounce window short so tests don't wait 5s.
  # 0.05s gives the scheduler thread time to enter its wait loop and fire.
  before { stub_const('Datadog::SymbolDatabase::Component::EXTRACT_DEBOUNCE_INTERVAL', 0.05) }

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
      stub_const('RUBY_VERSION', '2.5.0')
      expect(raw_logger).to receive(:debug) { |&block| expect(block.call).to match(/requires Ruby 2.6\+/) }
      expect(described_class.send(:environment_supported?, logger)).to be false
    end
  end

  describe '.build' do
    context 'when symbol_database is disabled' do
      before { settings.symbol_database.enabled = false }

      it 'returns nil' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_nil
      end
    end

    context 'when remote is disabled and force_upload is false' do
      before do
        settings.remote.enabled = false
        settings.symbol_database.internal.force_upload = false
      end

      it 'returns nil' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_nil
      end
    end

    context 'when remote is enabled' do
      before { settings.remote.enabled = true }

      it 'returns a Component' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_a(described_class)
      end
    end

    context 'when force_upload is enabled' do
      before { settings.symbol_database.internal.force_upload = true }

      it 'returns a Component' do
        result = described_class.build(settings, agent_settings, logger)
        expect(result).to be_a(described_class)
        result.shutdown!
      end

      it 'calls schedule_deferred_upload' do
        expect_any_instance_of(described_class).to receive(:schedule_deferred_upload)
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
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    context 'without Rails' do
      before do
        hide_const('ActiveSupport')
        hide_const('Rails::Railtie')
      end

      it 'calls start_upload immediately' do
        expect(component).to receive(:start_upload)
        component.schedule_deferred_upload
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

        # Provide Rails.application.config.eager_load so the auto-deferred
        # upload runs in this test (production-like config). stub_const
        # replaces the Rails module entirely.
        rails_config = Struct.new(:eager_load).new(true)
        rails_app = Struct.new(:config).new(rails_config)
        rails_module = Module.new
        rails_module.define_singleton_method(:application) { rails_app }
        stub_const('Rails', rails_module)
        stub_const('Rails::Railtie', Class.new)

        allow(::ActiveSupport).to receive(:on_load).with(:after_initialize) do |&block|
          after_init_callbacks << block
        end
      end

      it 'defers start_upload to ActiveSupport.on_load(:after_initialize)' do
        expect(component).not_to receive(:start_upload)
        component.schedule_deferred_upload
        expect(after_init_callbacks.size).to eq(1)
      end

      it 'callback triggers start_upload on the registering Component' do
        component.schedule_deferred_upload
        expect(component).to receive(:start_upload)
        after_init_callbacks.each(&:call)
      end

      it 'each Component registers its own callback (no class-level dedup of registration)' do
        # Per-instance design: each Component schedules its own deferred upload.
        # Old shut-down Components short-circuit their start_upload via @shutdown,
        # so the surviving Component is the one that actually triggers extraction.
        component2 = described_class.new(settings, agent_settings, logger)

        component.schedule_deferred_upload
        component2.schedule_deferred_upload

        expect(after_init_callbacks.size).to eq(2)

        component2.shutdown!
      end
    end
  end

  describe '#start_upload (debounced extraction)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'eventually triggers extract_and_upload after the debounce window' do
      expect(component).to receive(:extract_and_upload).and_call_original
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])

      component.start_upload
      expect(component.wait_for_idle(timeout: 5)).to be true
    end

    it 'coalesces multiple start_upload calls into a single extraction (debounce)' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      5.times { component.start_upload }
      component.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(1)
    end

    it 'does not extract when shut down' do
      component.shutdown!
      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
    end

    it 'sets last_upload_time and last_upload_scope_count after a successful upload' do
      file_scope1 = instance_double(Datadog::SymbolDatabase::Scope, scope_type: 'FILE', name: 'a.rb', scopes: [])
      file_scope2 = instance_double(Datadog::SymbolDatabase::Scope, scope_type: 'FILE', name: 'b.rb', scopes: [])
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([file_scope1, file_scope2])
      allow(component.instance_variable_get(:@scope_batcher)).to receive(:add_scope)
      allow(component.instance_variable_get(:@scope_batcher)).to receive(:flush)

      expect(component.last_upload_time).to be_nil
      expect(component.last_upload_scope_count).to be_nil

      component.start_upload
      component.wait_for_idle(timeout: 5)

      expect(component.last_upload_time).to be_a(Time)
      expect(component.last_upload_scope_count).to eq(2)
    end
  end

  describe '#wait_for_idle' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'returns true when an upload completes within the timeout' do
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all).and_return([])
      component.start_upload
      expect(component.wait_for_idle(timeout: 5)).to be true
    end

    it 'returns false when no upload happens within the timeout' do
      expect(component.wait_for_idle(timeout: 0.1)).to be false
    end
  end

  describe '#shutdown!' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    it 'sets the shutdown flag' do
      component.shutdown!
      expect(component.shutdown?).to be true
    end

    it 'prevents subsequent start_upload from extracting' do
      component.shutdown!
      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
      sleep 0.2
    end

    it 'cancels a pending debounced extraction' do
      extractor = component.instance_variable_get(:@extractor)
      expect(extractor).not_to receive(:extract_all)

      component.start_upload
      component.shutdown!  # before debounce fires
      sleep 0.2
    end

    it 'waits for an in-flight extraction to complete' do
      events = Queue.new
      extract_started = Queue.new
      release_extract = Queue.new

      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extract_started.push(:started)
        release_extract.pop
        events.push(:extract_returned)
        []
      end

      component.start_upload
      extract_started.pop  # extraction is in flight; @upload_in_progress is true

      shutdown_thread = Thread.new do
        component.shutdown!
        events.push(:shutdown_returned)
      end

      release_extract.push(:go)
      shutdown_thread.join(10)

      # shutdown! must not return until the in-flight extraction completes
      expect(events.pop).to eq(:extract_returned)
      expect(events.pop).to eq(:shutdown_returned)
      expect(component.upload_in_progress).to be false
    end
  end

  describe 'debounce regression (collapses bursts of start_upload calls)' do
    # The two-uploads bug was that a burst of start_upload triggers — auto-deferred
    # callback then explicit script call — produced two extractions. The fix is
    # the per-instance debounce scheduler: multiple start_upload calls within
    # EXTRACT_DEBOUNCE_INTERVAL coalesce into a single extraction.
    before do
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
      hide_const('ActiveSupport')
      hide_const('Rails::Railtie')
    end

    it 'multiple start_upload calls within the debounce window produce one extraction' do
      extraction_count = 0
      allow_any_instance_of(described_class).to receive(:extract_and_upload) do |_inst|
        extraction_count += 1
      end

      component = described_class.new(settings, agent_settings, logger)
      component.start_upload
      component.start_upload
      component.start_upload
      sleep 0.2 # > EXTRACT_DEBOUNCE_INTERVAL (0.05s), give scheduler time to fire

      expect(extraction_count).to eq(1)

      component.shutdown!
    end

    it 'each Component built across reconfigurations extracts independently' do
      # With hot-load coverage, dedup across Components is intentionally removed.
      # Each Component is responsible for its own initial extraction (which the
      # new Component needs in order to have a hot-load baseline) plus any
      # incremental extractions driven by the TracePoint :class hook.
      extraction_count = 0
      allow_any_instance_of(described_class).to receive(:extract_and_upload) do |_inst|
        extraction_count += 1
      end

      component_a = described_class.build(settings, agent_settings, logger)
      component_a.wait_for_idle(timeout: 5)
      component_a.shutdown!

      component_b = described_class.build(settings, agent_settings, logger)
      component_b.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(2)

      component_b.shutdown!
    end
  end

  describe 'hot-load coverage (TracePoint :class)' do
    # Verifies the cross-tracer parity goal (Java ClassFileTransformer,
    # Python BaseModuleWatchdog#after_import, .NET AppDomain.AssemblyLoad):
    # classes defined after initial extraction reach the symbol DB via
    # incremental uploads driven by the TracePoint :class hook.
    before do
      allow(settings.symbol_database.internal).to receive(:force_upload).and_return(true)
      hide_const('ActiveSupport')
      hide_const('Rails::Railtie')
    end

    it 'extracts a class defined after the initial upload completes' do
      extracted_modules = []
      allow_any_instance_of(Datadog::SymbolDatabase::Extractor).to receive(:extract) do |_inst, mod|
        extracted_modules << mod
        nil
      end

      component = described_class.build(settings, agent_settings, logger)
      component.wait_for_idle(timeout: 5)

      begin
        # Define a class — `class Foo` opens a class body, which fires
        # TracePoint :class. The hook buffers the class; the scheduler
        # drains and calls Extractor#extract.
        eval('class SymdbHotLoadSpecNewClass; def hello; end; end', binding, __FILE__, __LINE__) # rubocop:disable Security/Eval

        component.wait_for_idle(timeout: 5)

        expect(extracted_modules.map(&:name)).to include('SymdbHotLoadSpecNewClass')
      ensure
        Object.send(:remove_const, :SymdbHotLoadSpecNewClass) if Object.const_defined?(:SymdbHotLoadSpecNewClass)
        component.shutdown!
      end
    end
  end

  describe 'enable/disable upload (ported from Java SymDBEnablementTest.enableDisableSymDBThroughRC)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'extracts once when start_upload is called' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      component.start_upload
      component.wait_for_idle(timeout: 5)

      expect(extraction_count).to eq(1)
    end

    it 'stop_upload cancels a pending debounce so no extraction occurs' do
      extractor = component.instance_variable_get(:@extractor)
      expect(extractor).not_to receive(:extract_all)

      component.start_upload
      component.stop_upload
      sleep 0.2
    end

    it 'does not extract again after start, stop, re-start when already uploaded once this process' do
      extraction_count = 0
      allow(component.instance_variable_get(:@extractor)).to receive(:extract_all) do
        extraction_count += 1
        []
      end

      component.start_upload
      component.wait_for_idle(timeout: 5)
      component.stop_upload
      component.start_upload
      sleep 0.2

      expect(extraction_count).to eq(1)
    end
  end

  describe 'config removal (ported from Java SymDBEnablementTest.removeSymDBConfig)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    it 'shutdown prevents any future uploads' do
      allow(component).to receive(:extract_and_upload)

      component.start_upload
      component.shutdown!

      expect(component).not_to receive(:extract_and_upload)
      component.start_upload
      sleep 0.2
    end
  end

  describe 'filtering behavior (ported from Java SymDBEnablementTest.noIncludesFilterOutDatadogClass)' do
    let(:component) { described_class.new(settings, agent_settings, logger) }

    after { component.shutdown! }

    it 'extract_and_upload filters out Datadog internal classes' do
      uploaded_scopes = []
      mock_scope_batcher = instance_double(Datadog::SymbolDatabase::ScopeBatcher)
      allow(mock_scope_batcher).to receive(:add_scope) { |scope| uploaded_scopes << scope }
      allow(mock_scope_batcher).to receive(:flush)
      allow(mock_scope_batcher).to receive(:shutdown)
      component.instance_variable_set(:@scope_batcher, mock_scope_batcher)

      component.send(:extract_and_upload)

      datadog_scopes = uploaded_scopes.select { |s| s.name&.start_with?('Datadog::') }
      expect(datadog_scopes).to be_empty
    end
  end
end
