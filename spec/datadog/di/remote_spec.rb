require "datadog/di/spec_helper"
require 'spec_helper'

RSpec.describe Datadog::DI::Remote do
  di_test

  let(:remote) { described_class }
  let(:path) { 'datadog/2/LIVE_DEBUGGING/logProbe_uuid/hash' }

  before(:all) do
    # if code tracking is active, it invokes methods on mock objects
    # used in these tests.
    Datadog::DI.deactivate_tracking!
  end

  it 'declares the LIVE_DEBUGGING product' do
    expect(remote.products).to contain_exactly('LIVE_DEBUGGING')
  end

  it 'declares no capabilities' do
    expect(remote.capabilities).to eq []
  end

  it 'declares matches that match APM_TRACING' do
    telemetry = instance_double(Datadog::Core::Telemetry::Component)

    expect(remote.receivers(telemetry)).to all(
      match(
        lambda do |receiver|
          receiver.match? Datadog::Core::Remote::Configuration::Path.parse(path)
        end
      )
    )
  end

  describe '.receivers' do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    it 'returns receivers' do
      receivers = described_class.receivers(telemetry)
      expect(receivers.size).to eq(1)
      expect(receivers.first).to be_a(Datadog::Core::Remote::Dispatcher::Receiver)
    end

    describe 'receiver logic' do
      let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

      let(:transaction) do
        repository.transaction do |_repository, transaction|
          probe_configs.each do |key, value|
            value_json = value.to_json

            target = Datadog::Core::Remote::Configuration::Target.parse(
              {
                'custom' => {
                  'v' => 1,
                },
                'hashes' => {'sha256' => Digest::SHA256.hexdigest(value_json.to_json)},
                'length' => value_json.length
              }
            )

            content = Datadog::Core::Remote::Configuration::Content.parse(
              {
                path: key,
                content: StringIO.new(value_json),
              }
            )

            transaction.insert(content.path, target, content)
          end
        end
      end

      let(:probe_configs) do
        {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec}
      end

      let(:receiver) { described_class.receivers(telemetry)[0] }

      let(:probe_notifier_worker) do
        instance_double(Datadog::DI::ProbeNotifierWorker)
      end

      let(:component) do
        instance_double(Datadog::DI::Component).tap do |component|
          expect(component).to receive(:probe_manager).and_return(probe_manager)
          allow(component).to receive(:settings).and_return(settings)
        end
      end

      mock_settings_for_di do |settings|
        allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
        allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(false)
      end

      let(:serializer) do
        instance_double(Datadog::DI::Serializer)
      end

      let(:instrumenter) do
        Datadog::DI::Instrumenter.new(settings, serializer, logger)
      end

      let(:probe_notification_builder) do
        instance_double(Datadog::DI::ProbeNotificationBuilder)
      end

      let(:logger) do
        instance_double(Logger)
      end

      let(:probe_manager) do
        Datadog::DI::ProbeManager.new(settings, instrumenter, probe_notification_builder, probe_notifier_worker, logger)
      end

      let(:agent_settings) do
        double('agent settings')
      end

      let(:transport) do
        double('transport')
      end

      let(:notifier_worker) do
        Datadog::DI::ProbeNotifierWorker.new(settings, agent_settings, transport)
      end

      let(:stringified_probe_spec) do
        JSON.parse(probe_spec.to_json)
      end

      let(:telemetry) do
        instance_double(Datadog::Core::Telemetry::Component)
      end

      before do
        expect(Datadog::DI).to receive(:component).at_least(:once).and_return(component)
      end

      context 'new probe received' do
        let(:probe_spec) do
          {id: '11', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'Foo', methodName: 'bar'}}
        end

        it 'calls probe manager to add a probe' do
          expect(component).to receive(:logger).and_return(logger)
          expect(logger).to receive(:info) do |message|
            expect(message).to match(/Received probe/)
          end

          expect(probe_manager).to receive(:add_probe) do |probe|
            expect(probe.id).to eq('11')
          end
          expect(component).to receive(:probe_notification_builder).and_return(probe_notification_builder)
          expect(probe_notification_builder).to receive(:build_received)
          expect(component).to receive(:probe_notifier_worker).and_return(probe_notifier_worker)
          expect(probe_notifier_worker).to receive(:add_status)
          receiver.call(repository, transaction)
        end

        context 'probe addition raises an exception' do
          it 'logs warning and consumes the exception' do
            expect(component).to receive(:telemetry).and_return(telemetry)
            expect(component).to receive(:logger).and_return(logger)
            expect(logger).to receive(:info) do |message|
              expect(message).to match(/Received probe/)
            end

            expect(logger).to receive(:warn) do |msg|
              expect(msg).to match(/Unhandled exception.*Runtime error from test/)
            end
            expect(component).to receive(:logger).and_return(logger)
            expect(telemetry).to receive(:report)

            expect(probe_manager).to receive(:add_probe).and_raise("Runtime error from test")
            expect(component).to receive(:probe_notification_builder).and_return(probe_notification_builder)
            expect(probe_notification_builder).to receive(:build_received)
            expect(component).to receive(:probe_notifier_worker).and_return(probe_notifier_worker)
            expect(probe_notifier_worker).to receive(:add_status)
            expect do
              receiver.call(repository, transaction)
            end.not_to raise_error
          end
        end

        it 'calls probe manager to remove stale probes' do
          allow(component).to receive(:telemetry)
          expect(component).to receive(:logger).and_return(logger)
          expect(logger).to receive(:info) do |message|
            expect(message).to match(/Received probe/)
          end

          expect(logger).to receive(:warn) do |msg|
            expect(msg).to match(/Unhandled exception.*Runtime error from test/)
          end

          allow(probe_manager).to receive(:add_probe).and_raise("Runtime error from test")
          expect(component).to receive(:logger).and_return(logger)
          expect(component).to receive(:probe_notification_builder).and_return(probe_notification_builder)
          expect(probe_notification_builder).to receive(:build_received)
          expect(component).to receive(:probe_notifier_worker).and_return(probe_notifier_worker)
          expect(probe_notifier_worker).to receive(:add_status)

          expect(probe_manager).to receive(:remove_other_probes).with(['11'])
          receiver.call(repository, transaction)
        end

        context 'probe removal raises an exception' do
          it 'logs warning and consumes the exception' do
            expect(component).to receive(:telemetry).and_return(telemetry).at_least(:once)
            expect(component).to receive(:logger).and_return(logger)
            expect(logger).to receive(:info) do |message|
              expect(message).to match(/Received probe/)
            end

            expect(logger).to receive(:warn) do |msg|
              expect(msg).to match(/Unhandled exception.*Runtime error 1 from test/)
            end
            expect(telemetry).to receive(:report)

            allow(probe_manager).to receive(:add_probe).and_raise("Runtime error 1 from test")
            expect(component).to receive(:logger).and_return(logger)
            expect(component).to receive(:probe_notification_builder).and_return(probe_notification_builder)
            expect(probe_notification_builder).to receive(:build_received)
            expect(component).to receive(:probe_notifier_worker).and_return(probe_notifier_worker)
            expect(probe_notifier_worker).to receive(:add_status)

            expect(logger).to receive(:warn) do |msg|
              expect(msg).to match(/Unhandled exception.*Runtime error 2 from test/)
            end
            expect(component).to receive(:logger).and_return(logger)
            expect(telemetry).to receive(:report)

            expect(probe_manager).to receive(:remove_other_probes).with(['11']).and_raise("Runtime error 2 from test")
            expect do
              receiver.call(repository, transaction)
            end.not_to raise_error
          end
        end
      end
    end
  end
end
