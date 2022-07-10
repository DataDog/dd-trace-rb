require 'spec_helper'

require 'datadog/core/telemetry/client'

RSpec.describe Datadog::Core::Telemetry::Client do
  subject(:client) { described_class.new(enabled: enabled, sequence: sequence) }
  let(:enabled) { true }
  let(:sequence) { Datadog::Core::Utils::Sequence.new(1) }
  let(:emitter) { double(Datadog::Core::Telemetry::Emitter) }
  let(:response) { double(Datadog::Core::Telemetry::Http::Adapters::Net::Response) }
  let(:not_found) { false }

  before do
    allow(Datadog::Core::Telemetry::Emitter).to receive(:new).and_return(emitter)
    allow(emitter).to receive(:request).and_return(response)
    allow(response).to receive(:not_found?).and_return(not_found)
  end

  describe '#initialize' do
    after do
      client.worker.stop(true)
      client.worker.join
    end

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
      it { expect(client.worker.enabled?).to be(false) }
    end

    context 'when enabled' do
      let(:enabled) { true }

      it do
        client
        expect(emitter).to have_received(:request).with('app-started')
        expect(client.worker.enabled?).to be(true)
      end

      context 'when response returns 404' do
        let(:not_found) { true }

        before do
          logger = double(Datadog::Core::Logger)
          allow(logger).to receive(:debug)
          allow(Datadog).to receive(:logger).and_return(logger)
        end

        it do
          expect(client.enabled).to be(false)
          expect(client.unsupported).to be(true)
          expect(Datadog.logger).to have_received(:debug) do |message|
            expect(message).to eq('Agent does not support telemetry; disabling future telemetry events.')
          end
        end
      end
    end
  end

  describe '#disable!' do
    after do
      client.worker.stop(true)
      client.worker.join
    end

    it { expect { client.disable! }.to change { client.enabled }.from(true).to(false) }
    it { expect { client.disable! }.to change { client.worker.enabled? }.from(true).to(false) }
  end

  describe '#reenable!' do
    after do
      client.worker.stop(true)
      client.worker.join
    end

    context 'when already enabled' do
      it do
        expect(client.enabled).to be(true)
        expect(client.worker.enabled?).to be(true)

        client.reenable!

        expect(client.enabled).to be(true)
        expect(client.worker.enabled?).to be(true)
      end
    end

    context 'when disabled' do
      let(:enabled) { false }
      it { expect { client.reenable! }.to change { client.enabled }.from(false).to(true) }
      it { expect { client.reenable! }.to change { client.worker.enabled? }.from(false).to(true) }

      context 'when unsupported' do
        let(:unsupported_client) { client.instance_variable_set(:@unsupported, true) }
        before do
          allow(described_class).to receive(:new).and_return(unsupported_client)
        end

        it do
          expect(client.enabled).to be(false)
          expect(client.worker.enabled?).to be(false)

          client.reenable!

          expect(client.enabled).to be(false)
          expect(client.worker.enabled?).to be(false)
        end
      end
    end
  end

  describe '#started!' do
    subject(:started!) { client.started! }

    after do
      client.worker.stop(true)
      client.worker.join
    end

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

    context 'when internal error returned by emitter' do
      let(:response) { Datadog::Core::Telemetry::Http::InternalErrorResponse.new('error') }

      it do
        started!
        is_expected.to be(response)
      end
    end
  end

  describe '#stop!' do
    subject(:stop!) { client.stop! }
    let(:worker) { instance_double(Datadog::Core::Telemetry::Heartbeat) }

    before do
      allow(Datadog::Core::Telemetry::Heartbeat).to receive(:new).and_return(worker)
      allow(worker).to receive(:start)
      allow(worker).to receive(:stop)
      allow(worker).to receive(:join)
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        stop!
        expect(client.worker).to have_received(:stop)
        expect(client.worker).to have_received(:join)
        expect(emitter).to_not have_received(:request).with('app-closing')
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        stop!
        expect(client.worker).to have_received(:stop)
        expect(emitter).to have_received(:request).with('app-closing')
      end

      it { is_expected.to be(response) }

      context 'when stop! has been called already' do
        let(:stopped_client) { client.instance_variable_set(:@stopped, true) }

        before do
          allow(described_class).to receive(:new).and_return(stopped_client)
        end

        it do
          stop!

          expect(client.worker).to_not have_received(:stop)
          expect(emitter).to_not have_received(:request).with('app-closing')
        end
      end
    end
  end

  describe '#integrations_change!' do
    subject(:integrations_change!) { client.integrations_change! }

    after do
      client.worker.stop(true)
      client.worker.join
    end

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
