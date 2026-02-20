require 'spec_helper'

require 'datadog/core/telemetry/event/app_extended_heartbeat'

RSpec.describe Datadog::Core::Telemetry::Event::AppExtendedHeartbeat do
  let(:id) { double('seq_id') }
  subject(:event) { described_class.new(components: Datadog.send(:components)) }

  before do
    allow_any_instance_of(Datadog::Core::Utils::Sequence).to receive(:next).and_return(id)
  end

  describe '#type' do
    it 'returns app-extended-heartbeat' do
      expect(event.type).to eq('app-extended-heartbeat')
    end
  end

  describe '#app_started?' do
    it 'returns false' do
      expect(event.app_started?).to eq(false)
    end
  end

  describe '#payload' do
    subject(:payload) { event.payload }

    it 'contains configuration' do
      expect(payload).to have_key(:configuration)
      expect(payload[:configuration]).to be_a(Array)
    end

    it 'contains dependencies' do
      expect(payload).to have_key(:dependencies)
      expect(payload[:dependencies]).to be_a(Array)
    end

    it 'contains integrations' do
      expect(payload).to have_key(:integrations)
      expect(payload[:integrations]).to be_a(Array)
    end

    it 'does not contain products' do
      expect(payload).to_not have_key(:products)
    end

    it 'does not contain install_signature' do
      expect(payload).to_not have_key(:install_signature)
    end

    context 'dependencies' do
      it 'includes gem name and version' do
        expect(payload[:dependencies]).to all(
          match(hash_including(name: be_a(String), version: be_a(String)))
        )
      end
    end

    context 'integrations' do
      it 'includes integration details' do
        expect(payload[:integrations]).to all(
          match(hash_including(name: be_a(String), enabled: be_in([true, false])))
        )
      end
    end
  end
end
