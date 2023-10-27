require 'spec_helper'

require 'datadog/core/telemetry/client'

RSpec.describe Datadog::Core::Telemetry::Client do
  subject(:client) do
    described_class.new(
      enabled: enabled,
      metrics_enabled: metrics_enabled,
      heartbeat_interval_seconds: heartbeat_interval_seconds
    )
  end
  let(:enabled) { true }
  let(:metrics_enabled) { true }
  let(:heartbeat_interval_seconds) { 1.3 }
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
      client.metrics_worker.stop(true)
      client.metrics_worker.join
    end

    context 'with default parameters' do
      subject(:client) do
        described_class.new(heartbeat_interval_seconds: heartbeat_interval_seconds, metrics_enabled: metrics_enabled)
      end
      it { is_expected.to be_a_kind_of(described_class) }
      it { expect(client.enabled).to be(true) }
      it { expect(client.emitter).to be(emitter) }

      it 'set Metric::Rate interval value' do
        expect(Datadog::Core::Telemetry::Metric::Rate).to receive(:'interval=').with(heartbeat_interval_seconds)
        client
      end
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

    context 'when metrics is disabled' do
      let(:metrics_enabled) { false }

      it { expect(client.metrics_worker.enabled?).to be(false) }
    end

    context 'when metrics is enabled' do
      let(:metrics_enabled) { true }

      it { expect(client.metrics_worker.enabled?).to be(true) }
    end
  end

  describe '#disable!' do
    after do
      client.worker.stop(true)
      client.worker.join
      client.metrics_worker.stop(true)
      client.metrics_worker.join
    end

    it { expect { client.disable! }.to change { client.enabled }.from(true).to(false) }
    it { expect { client.disable! }.to change { client.worker.enabled? }.from(true).to(false) }
    it { expect { client.disable! }.to change { client.metrics_worker.enabled? }.from(true).to(false) }
  end

  describe '#started!' do
    subject(:started!) { client.started! }

    after do
      client.worker.stop(true)
      client.worker.join
      client.metrics_worker.stop(true)
      client.metrics_worker.join
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
      client.metrics_worker.stop(true)
      client.metrics_worker.join
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
      allow(Datadog::Core::Telemetry::Heartbeat).to receive(:new)
        .with(enabled: enabled, heartbeat_interval_seconds: heartbeat_interval_seconds).and_return(worker)
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
      client.metrics_worker.stop(true)
      client.metrics_worker.join
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

  describe '#client_configuration_change!' do
    subject(:client_configuration_change!) { client.client_configuration_change!(changes) }
    let(:changes) { double('changes') }

    after do
      client.worker.stop(true)
      client.worker.join
      client.metrics_worker.stop(true)
      client.metrics_worker.join
    end

    context 'when disabled' do
      let(:enabled) { false }
      it do
        client_configuration_change!
        expect(emitter).to_not have_received(:request)
      end
    end

    context 'when enabled' do
      let(:enabled) { true }
      it do
        client_configuration_change!
        expect(emitter).to have_received(:request).with(
          'app-client-configuration-change',
          data: { changes: changes, origin: 'remote_config' }
        )
      end

      it { is_expected.to be(response) }
    end

    context 'when in fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it do
        client
        expect_in_fork do
          client.started!
          expect(emitter).to_not have_received(:request)
        end
      end
    end
  end

  context 'metrics' do
    [
      [:add_count_metric, Datadog::Core::Telemetry::Metric::Count],
      [:add_rate_metric, Datadog::Core::Telemetry::Metric::Rate],
      [:add_gauge_metric, Datadog::Core::Telemetry::Metric::Gauge],
      [:add_distribution_metric, Datadog::Core::Telemetry::Metric::Distribution],
    ].each do |metric_method, metric_klass|
      context 'when disabled' do
        let(:metrics_enabled) { false }
        it do
          expect(client.send(metric_method, 'test_namespace', 'name', 1, {})).to be_nil
        end
      end

      context 'when enabled' do
        let(:metrics_enabled) { true }
        it do
          expect_any_instance_of(Datadog::Core::Telemetry::MetricQueue).to receive(:add_metric).with(
            'test_namespace',
            'name',
            1,
            {},
            metric_klass
          )
          client.send(metric_method, 'test_namespace', 'name', 1, {})
        end
      end
    end

    describe '#flush_metrics!' do
      after do
        client.worker.stop(true)
        client.worker.join
        client.metrics_worker.stop(true)
        client.metrics_worker.join
      end

      context 'when disabled' do
        let(:metrics_enabled) { false }
        it do
          expect(client.send(:flush_metrics!)).to be_nil
        end
      end

      context 'when enabled' do
        let(:metrics_enabled) { true }
        it 'send metrics to the emitter and reset the metric_queue' do
          old_metric_queue = client.instance_variable_get(:@metric_queue)

          client.add_distribution_metric('test_namespace', 'name', 1, {})
          expected_payload = {
            :namespace => 'test_namespace',
            :series => [
              {
                :metric => 'name', :tags => [], :values => [1],
                :type => 'distributions',
                :common => true
              }
            ]
          }
          expect(emitter).to receive(:request).with('distributions', payload: expected_payload)
          client.send(:flush_metrics!)

          new_metric_queue = client.instance_variable_get(:@metric_queue)
          expect(old_metric_queue).to_not eq new_metric_queue
        end
      end
    end
  end
end
