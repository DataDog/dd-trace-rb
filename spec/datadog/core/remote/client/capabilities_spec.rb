# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/client/capabilities'
require 'datadog/appsec/configuration'

RSpec.describe Datadog::Core::Remote::Client::Capabilities do
  subject(:capabilities) { described_class.new(settings, telemetry) }
  let(:settings) do
    double(Datadog::Core::Configuration)
  end
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  before do
    # Most of this spec asserts DI / symbol database registration, which only
    # happens on a runtime that can run them. Stub the platform checks so the
    # assertions hold across the full Ruby matrix (the real checks are false on
    # JRuby and old Rubies). The unsupported-runtime paths are covered below.
    allow(Datadog::DI).to receive(:supported_runtime?).and_return(true)
    allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(true)
  end

  shared_examples 'tracing and DI capabilities' do
    it 'includes tracing capabilities and the DI enablement bit' do
      # Bits 12, 13, 14, 29 (tracing) + 38 (DI enablement, registered with the DI block)
      expect(capabilities.base64_capabilities).to eq('QCAAcAA=')
    end
  end

  shared_examples 'tracing capabilities only' do
    it 'includes only tracing capabilities (DI not registered)' do
      # Bits 12, 13, 14, 29 (tracing). Bit 38 lives in the DI block, which is
      # not registered here (DI settings absent or explicitly disabled).
      expect(capabilities.base64_capabilities).to eq('IABwAA==')
    end
  end

  context 'AppSec component' do
    context 'when disabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.appsec.enabled = false
        settings
      end

      it 'does not register any capabilities, products, and receivers' do
        expect(capabilities.capabilities).to_not include(4)
        expect(capabilities.products).to_not include('ASM')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/1/ASM/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        # DI settings present and not explicitly disabled, so the DI block
        # (bit 38) is registered alongside the tracing capabilities.
        include_examples 'tracing and DI capabilities'
      end
    end

    context 'when not present' do
      it 'does not register any capabilities, products, and receivers' do
        expect(capabilities.capabilities).to_not include(4)
        expect(capabilities.products).to_not include('ASM')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/1/ASM/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        # Settings double responds to nothing, so neither AppSec nor DI is
        # registered — tracing capabilities only.
        include_examples 'tracing capabilities only'
      end
    end

    context 'when enabled' do
      let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine) }

      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.appsec.enabled = true
        settings
      end

      before do
        allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
      end

      it 'register capabilities, products, and receivers' do
        expect(capabilities.capabilities).to include(4)
        expect(capabilities.products).to include('ASM')
        expect(capabilities.receivers).to include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/1/ASM/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        it 'returns binary capabilities' do
          expect(capabilities.base64_capabilities).to_not be_empty
        end
      end
    end
  end

  context 'DI component' do
    context 'when explicitly disabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = false
        settings
      end

      it 'does not register DI capabilities, products, or receivers' do
        expect(capabilities.capabilities).to_not include(1 << 38)
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        include_examples 'tracing capabilities only'
      end
    end

    context 'when not present' do
      it 'does not register DI when settings are absent' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        # DI settings not present → no DI capabilities registered, and bit 38
        # now lives in the DI block, so it is absent too.
        include_examples 'tracing capabilities only'
      end
    end

    context 'when enabled or left at default' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings
      end

      it 'registers capabilities, products, and receivers' do
        expect(capabilities.capabilities).to include(1 << 38)
        expect(capabilities.products).to include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        include_examples 'tracing and DI capabilities'
      end
    end

    context 'when left at default (env var unset)' do
      let(:settings) { Datadog::Core::Configuration::Settings.new }

      it 'registers DI so remote configuration can enable it' do
        expect(capabilities.capabilities).to include(1 << 38)
        expect(capabilities.products).to include('LIVE_DEBUGGING')
      end

      describe '#base64_capabilities' do
        include_examples 'tracing and DI capabilities'
      end
    end

    context 'on an unsupported runtime (JRuby or Ruby 2.5)' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings
      end

      before do
        allow(Datadog::DI).to receive(:supported_runtime?).and_return(false)
      end

      it 'does not register DI capabilities, products, or receivers even when enabled' do
        expect(capabilities.capabilities).to_not include(1 << 38)
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        include_examples 'tracing capabilities only'
      end
    end
  end

  context 'Symbol Database component' do
    context 'when DI is disabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = false
        settings.symbol_database.enabled = true
        settings
      end

      # Symbol database registration is decoupled from DI: symbol_database
      # registers based on its own `enabled` setting alone, even when DI is
      # explicitly disabled and the DI block is skipped entirely.
      it 'registers symbol database product' do
        expect(capabilities.products).to include('LIVE_DEBUGGING_SYMBOL_DB')
      end
    end

    context 'when DI is enabled and symbol_database is disabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings.symbol_database.enabled = false
        settings
      end

      it 'does not register symbol database product' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
      end
    end

    context 'when DI is enabled and symbol_database is enabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings.symbol_database.enabled = true
        settings
      end

      it 'registers symbol database product and a receiver matching its path' do
        expect(capabilities.products).to include('LIVE_DEBUGGING_SYMBOL_DB')
        expect(capabilities.receivers).to include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING_SYMBOL_DB/_/_')
          }
        )
      end
    end

    context 'on an unsupported runtime (JRuby or Ruby < 2.7)' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings.symbol_database.enabled = true
        settings
      end

      before do
        allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(false)
      end

      it 'does not register the symbol database product or receiver even when enabled' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING_SYMBOL_DB/_/_')
          }
        )
      end
    end
  end

  context 'Tracing component' do
    it 'register capabilities, products, and receivers' do
      expect(capabilities.capabilities).to contain_exactly(1 << 12, 1 << 13, 1 << 14, 1 << 29)
      expect(capabilities.products).to include('APM_TRACING')
      expect(capabilities.receivers).to include(
        lambda { |r|
          r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/1/APM_TRACING/_/lib_config')
        }
      )
    end
  end

  # The receiver registration order is load-bearing: on a combined RC
  # dispatch (LIVE_DEBUGGING probe insert + APM_TRACING
  # dynamic_instrumentation_enabled=true in one transaction), the Tracing
  # receiver must run before the DI receiver so handle_rc_enablement starts
  # DI before the DI receiver processes the probe change. Reversing the
  # order silently drops the probe: the DI receiver runs against a stopped
  # component, drops the change, and the remote client only redispatches on
  # content hash changes, so a subsequent poll with the same probe content
  # never redelivers it.
  describe 'receiver registration order' do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.dynamic_instrumentation.enabled = true
      end
    end

    let(:apm_tracing_path) do
      Datadog::Core::Remote::Configuration::Path.parse('datadog/1/APM_TRACING/_/lib_config')
    end

    let(:live_debugging_path) do
      Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
    end

    it 'registers the Tracing receiver before the DI receiver' do
      tracing_index = capabilities.receivers.index { |r| r.match?(apm_tracing_path) }
      di_index = capabilities.receivers.index { |r| r.match?(live_debugging_path) }

      expect(tracing_index).not_to be_nil
      expect(di_index).not_to be_nil
      expect(tracing_index).to be < di_index
    end
  end

  describe '#capabilities_to_base64' do
    before do
      allow(capabilities).to receive(:capabilities).and_return(
        [
          1 << 1,
          1 << 2,
        ]
      )
    end

    it 'returns base64 string' do
      expect(capabilities.send(:capabilities_to_base64)).to eq('Bg==')
    end
  end
end
