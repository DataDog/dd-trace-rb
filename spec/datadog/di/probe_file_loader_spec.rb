require "datadog/di/spec_helper"
require 'datadog/di'
require 'datadog/di/probe_file_loader'
require 'spec_helper'

RSpec.describe Datadog::DI::ProbeFileLoader do
  di_test

  let(:loader) { described_class }

  describe '.load_now' do
    before do
      expect(Datadog::Core::Environment::Execution).to receive(:development?).and_return(false).at_least(:once)
      Datadog.send(:reset!)

      # Stop environment logger from printing configuration to standard output
      allow(Datadog::Core::Diagnostics::EnvironmentLogger).to receive(:log_configuration!)
    end

    after do
      Datadog.send(:reset!)
    end

    context 'valid file' do
      with_env DD_DYNAMIC_INSTRUMENTATION_ENABLED: 'true',
        DD_REMOTE_CONFIGURATION_ENABLED: 'true',
        DD_DYNAMIC_INSTRUMENTATION_PROBE_FILE: File.join(File.dirname(__FILE__), 'probe_files', 'one.json')

      context 'when component tree is not initialized' do
        it 'creates component tree' do
          expect(Datadog.send(:components, allow_initialization: false)).to be nil
          described_class.load_now
          expect(Datadog.send(:components, allow_initialization: false)).to be_a(Datadog::Core::Configuration::Components)
        end
      end

      it 'parses and adds probes' do
        expect_any_instance_of(Datadog::DI::ProbeManager).to receive(:add_probe) do |_, probe|
          expect(probe).to be_a(Datadog::DI::Probe)
          expect(probe.id).to eq("100c9a5c-45ad-49dc-818b-c570d31e11d1")
          expect(probe.type).to eq(:log)
        end
        described_class.load_now
      end
    end

    context 'malformed file' do
      with_env DD_DYNAMIC_INSTRUMENTATION_ENABLED: 'true',
        DD_REMOTE_CONFIGURATION_ENABLED: 'true',
        DD_DYNAMIC_INSTRUMENTATION_PROBE_FILE: File.join(File.dirname(__FILE__), 'probe_files', 'bogus.json')

      before do
        # We want to assert that the exception is the expected one, which
        # requires a logger, which in turn requires component tree to be
        # initialized.
        Datadog.configure do
        end
      end

      it 'does not raise exceptions' do
        expect_any_instance_of(Datadog::DI::ProbeManager).not_to receive(:add_probe)
        expect_lazy_log_at_least(Datadog.logger, :debug, /di: unhandled exception handling a probe in DI probe file loader: JSON::ParserError:.*Malformed/) do
          described_class.load_now
        end
      end
    end

    context 'missing file' do
      with_env DD_DYNAMIC_INSTRUMENTATION_ENABLED: 'true',
        DD_REMOTE_CONFIGURATION_ENABLED: 'true',
        DD_DYNAMIC_INSTRUMENTATION_PROBE_FILE: File.join(File.dirname(__FILE__), 'probe_files', 'missing.json')

      it 'does not raise exceptions' do
        expect_any_instance_of(Datadog::DI::ProbeManager).not_to receive(:add_probe)
        described_class.load_now
      end
    end

    context 'when DI initialization fails' do
      with_env DD_DYNAMIC_INSTRUMENTATION_ENABLED: 'true',
        DD_REMOTE_CONFIGURATION_ENABLED: 'true',
        DD_DYNAMIC_INSTRUMENTATION_PROBE_FILE: File.join(File.dirname(__FILE__), 'probe_files', 'one.json')

      it 'does not raise exceptions' do
        expect_any_instance_of(Datadog::DI::ProbeManager).not_to receive(:add_probe)
        expect(Datadog::DI::Component).to receive(:new).and_raise("Test failure")
        described_class.load_now
      end
    end
  end

  describe '.load_now_or_later' do
    # The case of being in a rails app is handled by
    # spec/datadog/di/contrib/probe_file_loader_spec.rb.
    context 'not in rails app' do
      before do
        expect(Datadog::Core::Contrib::Rails::Utils.railtie_supported?).to be false
      end

      after do
        Datadog.send(:reset!)
      end

      it 'calls load_now' do
        expect(described_class).to receive(:load_now)
        described_class.load_now_or_later
      end
    end
  end
end
