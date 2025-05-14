require 'spec_helper'

require 'datadog/core/telemetry/component'

RSpec.describe Datadog::Core::Telemetry::Component do
  subject(:telemetry) do
    described_class.new(
      settings: settings,
      agent_settings: agent_settings,
      logger: logger,
      enabled: enabled,
    )
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |c|
      c.telemetry.enabled = enabled
      c.telemetry.metrics_enabled = metrics_enabled
      c.telemetry.log_collection_enabled = log_collection_enabled
      c.telemetry.heartbeat_interval_seconds = heartbeat_interval_seconds
      c.telemetry.metrics_aggregation_interval_seconds = metrics_aggregation_interval_seconds
      c.telemetry.shutdown_timeout_seconds = shutdown_timeout_seconds
      c.telemetry.dependency_collection = dependency_collection
    end
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  let(:enabled) { true }
  let(:metrics_enabled) { true }
  let(:log_collection_enabled) { true }
  let(:heartbeat_interval_seconds) { 0 }
  let(:metrics_aggregation_interval_seconds) { 1 }
  let(:shutdown_timeout_seconds) { 1 }
  let(:dependency_collection) { true }
  let(:worker) { double(Datadog::Core::Telemetry::Worker) }
  let(:transport) { double(Datadog::Core::Telemetry::Transport::Telemetry::Transport) }
  let(:not_found) { false }

  let(:logger) do
    instance_double(Logger)
  end

  before do
    allow(Datadog::Core::Telemetry::Worker).to receive(:new).with(
      logger: logger,
      heartbeat_interval_seconds: heartbeat_interval_seconds,
      metrics_aggregation_interval_seconds: metrics_aggregation_interval_seconds,
      dependency_collection: dependency_collection,
      enabled: enabled,
      emitter: an_instance_of(Datadog::Core::Telemetry::Emitter),
      metrics_manager: anything,
      shutdown_timeout: shutdown_timeout_seconds
    ).and_return(worker)

    allow(worker).to receive(:start)
    allow(worker).to receive(:enqueue)
    allow(worker).to receive(:stop)
    allow(worker).to receive(:"enabled=")
  end

  describe '.build' do
    subject(:telemetry) { described_class.build(settings, agent_settings, logger) }

    context 'when agentless' do
      before do
        expect(settings.telemetry).to receive(:agentless_enabled).at_least(:once).and_return(true)
      end

      context 'with api_key specified' do
        before do
          expect(settings).to receive(:api_key).at_least(:once).and_return('1234')
        end

        it 'enables telemetry' do
          expect(telemetry.enabled).to be true
          expect(telemetry.worker).to be worker
        end
      end

      context 'with api_key not specified' do
        before do
          expect(settings).to receive(:api_key).and_return(nil)
        end

        it 'disables telemetry' do
          expect_lazy_log(
            logger,
            :debug,
            /Telemetry disabled. Agentless telemetry requires a DD_API_KEY variable to be set/
          )
          expect(telemetry.enabled).to be false
          expect(telemetry.worker).to be nil
        end
      end
    end
  end

  describe '#initialize' do
    after do
      telemetry.stop!
    end

    context 'with default parameters' do
      subject(:telemetry) do
        described_class.new(
          enabled: enabled,
          logger: logger,
          settings: settings,
          agent_settings: agent_settings,
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

    context 'when in fork', skip: ENV['BATCHED_TASKS'] do
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

    context 'when in fork', skip: ENV['BATCHED_TASKS'] do
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

    context 'when in fork', skip: ENV['BATCHED_TASKS'] do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        telemetry
        expect_in_fork do
          expect(worker).not_to have_received(:enqueue)
        end
      end
    end
  end

  describe 'includes Datadog::Core::Telemetry::Logging' do
    after do
      telemetry.stop!
    end

    it { is_expected.to a_kind_of(Datadog::Core::Telemetry::Logging) }
  end

  describe '#log!' do
    after do
      telemetry.stop!
    end

    describe 'when enabled and log_collection_enabled is enabled' do
      let(:enabled) { true }
      let(:log_collection_enabled) { true }

      it do
        event = instance_double(Datadog::Core::Telemetry::Event::Log)
        telemetry.log!(event)

        expect(worker).to have_received(:enqueue).with(event)
      end

      context 'when in fork', skip: !Process.respond_to?(:fork) || ENV['BATCHED_TASKS'] do
        it do
          telemetry
          expect_in_fork do
            event = instance_double(Datadog::Core::Telemetry::Event::Log)
            telemetry.log!(event)

            expect(worker).not_to have_received(:enqueue)
          end
        end
      end
    end

    describe 'when disabled' do
      let(:enabled) { false }

      it do
        event = instance_double(Datadog::Core::Telemetry::Event::Log)
        telemetry.log!(event)

        expect(worker).not_to have_received(:enqueue)
      end
    end

    describe 'when log_collection_enabled is disabled' do
      let(:log_collection_enabled) { false }

      it do
        event = instance_double(Datadog::Core::Telemetry::Event::Log)
        telemetry.log!(event)

        expect(worker).not_to have_received(:enqueue)
      end
    end
  end

  context 'metrics support' do
    let(:metrics_manager) { spy(:metrics_manager) }
    let(:namespace) { double('namespace') }
    let(:metric_name) { double('metric_name') }
    let(:value) { double('value') }
    let(:tags) { double('tags') }
    let(:common) { double('common') }

    before do
      expect(Datadog::Core::Telemetry::MetricsManager).to receive(:new).with(
        aggregation_interval: metrics_aggregation_interval_seconds,
        enabled: enabled && metrics_enabled
      ).and_return(metrics_manager)
    end

    describe '#inc' do
      subject(:inc) { telemetry.inc(namespace, metric_name, value, tags: tags, common: common) }

      it do
        inc

        expect(metrics_manager).to have_received(:inc).with(
          namespace, metric_name, value, tags: tags, common: common
        )
      end
    end

    describe '#dec' do
      subject(:dec) { telemetry.dec(namespace, metric_name, value, tags: tags, common: common) }

      it do
        dec

        expect(metrics_manager).to have_received(:dec).with(
          namespace, metric_name, value, tags: tags, common: common
        )
      end
    end

    describe '#gauge' do
      subject(:gauge) { telemetry.gauge(namespace, metric_name, value, tags: tags, common: common) }

      it do
        gauge

        expect(metrics_manager).to have_received(:gauge).with(
          namespace, metric_name, value, tags: tags, common: common
        )
      end
    end

    describe '#rate' do
      subject(:rate) { telemetry.rate(namespace, metric_name, value, tags: tags, common: common) }

      it do
        rate

        expect(metrics_manager).to have_received(:rate).with(
          namespace, metric_name, value, tags: tags, common: common
        )
      end
    end

    describe '#distribution' do
      subject(:distribution) { telemetry.distribution(namespace, metric_name, value, tags: tags, common: common) }

      it do
        distribution

        expect(metrics_manager).to have_received(:distribution).with(
          namespace, metric_name, value, tags: tags, common: common
        )
      end
    end
  end
end
