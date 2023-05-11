# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/client/capabilities'
require 'datadog/appsec/configuration'

RSpec.describe Datadog::Core::Remote::Client::Capabilities do
  subject(:capabilities) { described_class.new(appsec_enabled) }

  before do
    capabilities
  end

  context 'when no component enabled' do
    let(:appsec_enabled) { false }

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

  context 'when a component enabled' do
    let(:appsec_enabled) { true }

    it 'register capabilities, products, and receivers' do
      expect(capabilities.capabilities).to_not be_empty
      expect(capabilities.products).to_not be_empty
      expect(capabilities.receivers).to_not be_empty
    end

    describe '#base64_capabilities' do
      it 'returns binary capabilities' do
        expect(capabilities.base64_capabilities).to eq('/A==')
      end
    end
  end
end
