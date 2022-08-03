require 'spec_helper'

require 'datadog/core/telemetry/client'

RSpec.describe Datadog::Core::Telemetry::Client do
  subject(:client) { described_class.new(enabled: enabled) }
  let(:enabled) { true }
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

      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(true) }
      it { expect(client.worker.enabled?).to be(true) }
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
        expect(emitter).to_not have_received(:request).with(:'app-started')
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

    context 'when response returns 404' do
      let(:not_found) { true }

      before do
        logger = double(Datadog::Core::Logger)
        allow(logger).to receive(:debug).with(any_args)
        allow(Datadog).to receive(:logger).and_return(logger)
      end

      it do
        started!
        expect(client.enabled).to be(false)
        expect(client.unsupported).to be(true)
        expect(Datadog.logger).to have_received(:debug).with(
          'Agent does not support telemetry; disabling future telemetry events.'
        )
      end
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!
          expect(emitter).to_not receive(:request).with(:'app-started')
        end
      end
    end
  end

  describe '#emit_closing!' do
    subject(:emit_closing!) { client.emit_closing! }

    after do
      client.worker.stop(true)
      client.worker.join
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        emit_closing!
        expect(emitter).to_not have_received(:request).with(:'app-closing')
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        emit_closing!
        expect(emitter).to have_received(:request).with(:'app-closing')
      end

      it { is_expected.to be(response) }
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!
          expect(emitter).to_not receive(:request).with(:'app-closing')
        end
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
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        stop!
        expect(client.worker).to have_received(:stop)
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        stop!
        expect(client.worker).to have_received(:stop)
      end

      context 'when stop! has been called already' do
        let(:stopped_client) { client.instance_variable_set(:@stopped, true) }

        before do
          allow(described_class).to receive(:new).and_return(stopped_client)
        end

        it do
          stop!

          expect(client.worker).to_not have_received(:stop)
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
        expect(emitter).to_not have_received(:request).with(:'app-integrations-change')
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        integrations_change!
        expect(emitter).to have_received(:request).with(:'app-integrations-change')
      end

      it { is_expected.to be(response) }
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!
          expect(emitter).to_not receive(:request).with(:'app-integrations-change')
        end
      end
    end
  end
end
