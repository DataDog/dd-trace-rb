require 'spec_helper'

require 'datadog/core/telemetry/component'

RSpec.describe Datadog::Core::Telemetry::Component do
  subject(:telemetry) do
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
    allow(Datadog::Core::Telemetry::Worker).to receive(:new).with(
      heartbeat_interval_seconds: heartbeat_interval_seconds,
      dependency_collection: dependency_collection,
      enabled: enabled,
      emitter: an_instance_of(Datadog::Core::Telemetry::Emitter)
    ).and_return(worker)

    allow(worker).to receive(:start)
    allow(worker).to receive(:enqueue)
    allow(worker).to receive(:stop)
    allow(worker).to receive(:"enabled=")
  end

  describe '#initialize' do
    after do
      telemetry.stop!
    end

    context 'with default parameters' do
      subject(:telemetry) do
        described_class.new(
          heartbeat_interval_seconds: heartbeat_interval_seconds,
          dependency_collection: dependency_collection
        )
      end

      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(telemetry.enabled).to be(true) }
    end

    context 'when :enabled is false' do
      let(:enabled) { false }
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(telemetry.enabled).to be(false) }
    end

    context 'when enabled' do
      let(:enabled) { true }

      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(telemetry.enabled).to be(true) }
    end
  end

  describe '#disable!' do
    after do
      telemetry.stop!
    end

    it { expect { telemetry.disable! }.to change { telemetry.enabled }.from(true).to(false) }

    it 'disables worker' do
      telemetry.disable!

      expect(worker).to have_received(:"enabled=").with(false)
    end
  end

  describe '#emit_closing!' do
    subject(:emit_closing!) { telemetry.emit_closing! }

    after do
      telemetry.stop!
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
        telemetry
        expect_in_fork do
          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end

  describe '#stop!' do
    subject(:stop!) { telemetry.stop! }

    it 'stops worker once' do
      stop!
      stop!

      expect(worker).to have_received(:stop).once
    end
  end

  describe '#integrations_change!' do
    subject(:integrations_change!) { telemetry.integrations_change! }

    after do
      telemetry.stop!
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
        telemetry
        expect_in_fork do
          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end

  describe '#client_configuration_change!' do
    subject(:client_configuration_change!) { telemetry.client_configuration_change!(changes) }
    let(:changes) { double('changes') }

    after do
      telemetry.stop!
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
        telemetry
        expect_in_fork do
          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end
end
