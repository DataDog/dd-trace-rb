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
        appsec_settings = Datadog::AppSec::Configuration::Settings.new
        dsl = Datadog::AppSec::Configuration::DSL.new
        dsl.enabled = false
        appsec_settings.merge(dsl)

        settings = Datadog::Core::Configuration::Settings.new
        expect(settings).to receive(:appsec).at_least(:once).and_return(appsec_settings)

        settings
      end

      it 'does not register any capabilities, products, and receivers' do
        expect(capabilities.capabilities).to be_empty
        expect(capabilities.products).to be_empty
        expect(capabilities.receivers).to be_empty
      end

      describe '#base64_capabilities' do
        it 'returns an empty string' do
          expect(capabilities.base64_capabilities).to eq('')
        end
      end
    end

    context 'when not present' do
      it 'does not register any capabilities, products, and receivers' do
        expect(capabilities.capabilities).to be_empty
        expect(capabilities.products).to be_empty
        expect(capabilities.receivers).to be_empty
      end

      describe '#base64_capabilities' do
        it 'returns an empty string' do
          expect(capabilities.base64_capabilities).to eq('')
        end
      end
    end

    context 'when enabled' do
      let(:settings) do
        appsec_settings = Datadog::AppSec::Configuration::Settings.new
        dsl = Datadog::AppSec::Configuration::DSL.new
        dsl.enabled = true
        appsec_settings.merge(dsl)

        settings = Datadog::Core::Configuration::Settings.new
        expect(settings).to receive(:appsec).and_return(appsec_settings)

        settings
      end

      it 'register capabilities, products, and receivers' do
        expect(capabilities.capabilities).to_not be_empty
        expect(capabilities.products).to_not be_empty
        expect(capabilities.receivers).to_not be_empty
      end

      describe '#base64_capabilities' do
        it 'returns binary capabilities' do
          expect(capabilities.base64_capabilities).to_not be_empty
        end
      end
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
