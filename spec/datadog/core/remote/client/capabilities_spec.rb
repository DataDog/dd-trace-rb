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

      it 'registers the DI capability and receiver but defers the LIVE_DEBUGGING product' do
        expect(capabilities.capabilities).to include(1 << 38)
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
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

      it 'registers the DI capability so remote configuration can enable it; product deferred' do
        expect(capabilities.capabilities).to include(1 << 38)
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
      end

      describe '#base64_capabilities' do
        include_examples 'tracing and DI capabilities'
      end
    end

    context 'on an unsupported runtime' do
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
    context 'when DI is disabled and symbol_database is explicitly enabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = false
        settings.symbol_database.enabled = true
        settings
      end

      it 'registers symbol database product (explicit opt-in is independent of DI)' do
        expect(capabilities.products).to include('LIVE_DEBUGGING_SYMBOL_DB')
      end
    end

    context 'when DI is disabled and symbol_database is unset (nil)' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = false
        settings
      end

      it 'does not register symbol database product (nil follows DI setting)' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
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

    context 'when DI is enabled and symbol_database is unset (nil)' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings
      end

      it 'defers the symbol database product (mirrors DI; added when DI starts)' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
      end
    end

    context 'when DI is in its default state (unset) and symbol_database is unset (nil)' do
      let(:settings) { Datadog::Core::Configuration::Settings.new }

      it 'defers the symbol database product (mirrors DI; added when DI starts)' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
      end
    end

    context 'when the runtime does not support Symbol Database and symbol_database is unset (nil)' do
      let(:settings) { Datadog::Core::Configuration::Settings.new }

      before { allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(false) }

      it 'registers neither product at build time but still advertises the DI capability' do
        expect(capabilities.capabilities).to include(1 << 38)
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
        expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
      end
    end

    context 'on an unsupported runtime' do
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

  describe 'runtime product subscription' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    it '#products returns a snapshot copy that does not mutate the internal list' do
      snapshot = capabilities.products
      snapshot << 'LIVE_DEBUGGING'
      expect(capabilities.products).to_not include('LIVE_DEBUGGING')
    end

    it '#add_products advertises a product on the next read' do
      expect(capabilities.products).to_not include('LIVE_DEBUGGING')
      capabilities.add_products(['LIVE_DEBUGGING'])
      expect(capabilities.products).to include('LIVE_DEBUGGING')
    end

    it '#add_products is idempotent' do
      capabilities.add_products(['LIVE_DEBUGGING'])
      capabilities.add_products(['LIVE_DEBUGGING'])
      expect(capabilities.products.count('LIVE_DEBUGGING')).to eq(1)
    end

    it '#remove_products withdraws products' do
      capabilities.add_products(['LIVE_DEBUGGING', 'LIVE_DEBUGGING_SYMBOL_DB'])
      capabilities.remove_products(['LIVE_DEBUGGING', 'LIVE_DEBUGGING_SYMBOL_DB'])
      expect(capabilities.products).to_not include('LIVE_DEBUGGING')
      expect(capabilities.products).to_not include('LIVE_DEBUGGING_SYMBOL_DB')
    end

    it '#remove_products leaves other products intact' do
      capabilities.remove_products(['LIVE_DEBUGGING'])
      expect(capabilities.products).to include('APM_TRACING')
    end
  end
end
