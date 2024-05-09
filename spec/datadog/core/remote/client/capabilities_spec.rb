# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/client/capabilities'
require 'datadog/appsec/configuration'

RSpec.describe Datadog::Core::Remote::Client::Capabilities do
  subject(:capabilities) { described_class.new(settings) }
  let(:settings) do
    double(Datadog::Core::Configuration)
  end

  before do
    capabilities
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
        it 'matches tracing capabilities only' do
          expect(capabilities.base64_capabilities).to eq('IAAAAA==')
        end
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
        it 'matches tracing capabilities only' do
          expect(capabilities.base64_capabilities).to eq('IAAAAA==')
        end
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

  context 'Tracing component' do
    it 'register capabilities, products, and receivers' do
      expect(capabilities.capabilities).to eq([1 << 29])
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
