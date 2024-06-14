require 'spec_helper'

require 'datadog/core/telemetry/client'

RSpec.describe Datadog::Core::Telemetry::Client do
  subject(:client) do
    described_class.new(
      enabled: enabled,
      heartbeat_interval_seconds: heartbeat_interval_seconds,
      dependency_collection: dependency_collection
    )
  end

  let(:enabled) { true }
  let(:heartbeat_interval_seconds) { 0 }
  let(:dependency_collection) { true }
  let(:worker) { double(Datadog::Core::Telemetry::Worker) }
  let(:not_found) { false }

  before do
    allow(Datadog::Core::Telemetry::Worker).to receive(:new).and_return(worker)
    allow(worker).to receive(:start)
    allow(worker).to receive(:enqueue)
    allow(worker).to receive(:stop)
    allow(worker).to receive(:"enabled=")
  end

  describe '#initialize' do
    after do
      client.stop!
    end

    context 'with default parameters' do
      subject(:client) do
        described_class.new(
          heartbeat_interval_seconds: heartbeat_interval_seconds,
          dependency_collection: dependency_collection
        )
      end

      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(true) }
    end

    context 'when :enabled is false' do
      let(:enabled) { false }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(false) }
    end

    context 'when enabled' do
      let(:enabled) { true }

      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(true) }
    end
  end

  describe '#disable!' do
    after do
      client.stop!
    end

    it { expect { client.disable! }.to change { client.enabled }.from(true).to(false) }

    it 'disables worker' do
      client.disable!

      expect(worker).to have_received(:"enabled=").with(false)
    end
  end

  describe '#started!' do
    subject(:started!) { client.started! }

    after do
      client.stop!
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        started!

        expect(worker).to_not have_received(:start)
      end
    end

    context 'when enabled' do
      let(:enabled) { true }

      context 'when dependency_collection is true' do
        it do
          started!

          expect(worker).to have_received(:enqueue).with(
            an_instance_of(Datadog::Core::Telemetry::Event::AppDependenciesLoaded)
          )
        end
      end

      context 'when dependency_collection is false' do
        let(:dependency_collection) { false }

        it do
          started!

          expect(worker).not_to have_received(:enqueue)
        end
      end
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!

          expect(worker).to_not have_received(:start)
        end
      end
    end
  end

  describe '#emit_closing!' do
    subject(:emit_closing!) { client.emit_closing! }

    after do
      client.stop!
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        emit_closing!

        expect(worker).not_to have_received(:enqueue)
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        emit_closing!

        expect(worker).to have_received(:enqueue).with(
          an_instance_of(Datadog::Core::Telemetry::Event::AppClosing)
        )
      end
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!

          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end

  describe '#stop!' do
    subject(:stop!) { client.stop! }

    it 'stops worker once' do
      stop!
      stop!

      expect(worker).to have_received(:stop).once
    end
  end

  describe '#integrations_change!' do
    subject(:integrations_change!) { client.integrations_change! }

    after do
      client.stop!
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        integrations_change!

        expect(worker).not_to have_received(:enqueue)
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        integrations_change!

        expect(worker).to have_received(:enqueue).with(
          an_instance_of(Datadog::Core::Telemetry::Event::AppIntegrationsChange)
        )
      end
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!

          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end

  describe '#client_configuration_change!' do
    subject(:client_configuration_change!) { client.client_configuration_change!(changes) }
    let(:changes) { double('changes') }

    after do
      client.stop!
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        client_configuration_change!

        expect(worker).not_to have_received(:enqueue)
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        client_configuration_change!

        expect(worker).to have_received(:enqueue).with(
          an_instance_of(Datadog::Core::Telemetry::Event::AppClientConfigurationChange)
        )
      end
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!

          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end
end
