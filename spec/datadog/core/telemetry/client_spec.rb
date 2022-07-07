require 'spec_helper'

require 'datadog/core/telemetry/client'

RSpec.describe Datadog::Core::Telemetry::Client do
  subject(:client) { described_class.new(enabled: enabled, sequence: sequence) }
  let(:enabled) { true }
  let(:sequence) { Datadog::Core::Utils::Sequence.new(1) }
  let(:emitter) { double(Datadog::Core::Telemetry::Emitter) }
  let(:response) { double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }

  before do
    allow(Datadog::Core::Telemetry::Emitter).to receive(:new).and_return(emitter)
    allow(emitter).to receive(:request).and_return(response)
  end

  describe '#initialize' do
    context 'when no params provided' do
      subject(:client) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(true) }
      it { expect(client.emitter).to be(emitter) }
    end

    context 'when :enabled is false' do
      let(:enabled) { false }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(false) }
    end

    context 'when enabled' do
      let(:enabled) { true }

      it do
        client

        expect(emitter).to have_received(:request).with('app-started')
      end
    end
  end

  describe '#disable!' do
    it { expect { client.disable! }.to change { client.enabled }.from(true).to(false) }
  end

  describe '#started!' do
    subject(:started!) { client.started! }

    context 'when disabled' do
      let(:enabled) { false }
      it do
        started!
        expect(emitter).to_not have_received(:request).with('app-started')
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        started!
        is_expected.to be(response)
      end
    end
  end

  describe '#stop!' do
    subject(:stop!) { client.stop! }
    context 'when disabled' do
      let(:enabled) { false }
      it do
        stop!
        expect(emitter).to_not have_received(:request).with('app-closing')
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        stop!
        expect(emitter).to have_received(:request).with('app-closing')
      end

      it { is_expected.to be(response) }
    end
  end

  describe '#integrations_change!' do
    subject(:integrations_change!) { client.integrations_change! }
    context 'when disabled' do
      let(:enabled) { false }
      it do
        integrations_change!
        expect(emitter).to_not have_received(:request).with('app-integrations-change')
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        integrations_change!
        expect(emitter).to have_received(:request).with('app-integrations-change')
      end

      it { is_expected.to be(response) }
    end
  end
end
