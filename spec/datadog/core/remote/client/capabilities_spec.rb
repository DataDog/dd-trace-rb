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
    capabilities
  end

  shared_examples 'matches tracing capabilities only' do
    it 'matches tracing capabilities only' do
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
        include_examples 'matches tracing capabilities only'
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
        include_examples 'matches tracing capabilities only'
      end
    end

    context 'when enabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.appsec.enabled = true
        settings
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
    context 'when disabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = false
        settings
      end

      it 'does not register any capabilities, products, and receivers' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        include_examples 'matches tracing capabilities only'
      end
    end

    context 'when not present' do
      it 'does not register any capabilities, products, and receivers' do
        expect(capabilities.products).to_not include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to_not include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        include_examples 'matches tracing capabilities only'
      end
    end

    context 'when enabled' do
      let(:settings) do
        settings = Datadog::Core::Configuration::Settings.new
        settings.dynamic_instrumentation.enabled = true
        settings
      end

      it 'register capabilities, products, and receivers' do
        expect(capabilities.products).to include('LIVE_DEBUGGING')
        expect(capabilities.receivers).to include(
          lambda { |r|
            r.match? Datadog::Core::Remote::Configuration::Path.parse('datadog/2/LIVE_DEBUGGING/_/_')
          }
        )
      end

      describe '#base64_capabilities' do
        # DI does not contain any additional capabilities at this time
        include_examples 'matches tracing capabilities only'
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
