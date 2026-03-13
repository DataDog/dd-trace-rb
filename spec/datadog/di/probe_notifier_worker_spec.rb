require "datadog/di/spec_helper"
require "datadog/di/probe_notifier_worker"
require 'logger'

RSpec.describe Datadog::DI::ProbeNotifierWorker do
  di_test

  before do
    # The tests in this file assert on generated payloads which may include
    # SCM tags.
    Datadog::Core::Environment::Git.reset_for_tests
    Datadog::Core::TagBuilder.reset_for_tests
  end

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(false)
    # Reduce to 1 to have the test run faster
    allow(settings.dynamic_instrumentation.internal).to receive(:min_send_interval).and_return(1)
    allow(settings.dynamic_instrumentation.internal).to receive(:snapshot_queue_capacity).and_return(10)

    # ddtags
    allow(settings).to receive(:tags).and_return({})
    allow(settings).to receive(:env)
    allow(settings).to receive(:service)
    allow(settings).to receive(:version)
  end

  let(:agent_settings) do
    instance_double_agent_settings
  end

  di_logger_double

  let(:telemetry) { nil }

  let(:worker) { described_class.new(settings, logger, agent_settings: agent_settings, telemetry: telemetry) }

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
  end

  after do
    worker.stop
  end

  context 'not started' do
    describe '#add_snapshot' do
      let(:snapshot) do
        {hello: 'world'}
      end

      it 'adds snapshot to queue' do
        # Depending on scheduling, the worker thread may attempt to
        # invoke the transport to send the snapshot.
        allow(input_transport).to receive(:send_input)

        expect(worker.send(:snapshot_queue)).to be_empty

        worker.add_snapshot(snapshot)

        expect(worker.send(:snapshot_queue)).to eq([snapshot])
      end
    end
  end

  describe '#stop' do
    context 'worker is running' do
      before do
        worker.start
      end

      it 'stops the thread' do
        worker.stop
        expect(worker.send(:thread)).to be nil
      end
    end

    context 'worker is not running' do
      before do
        expect(worker.send(:thread)).to be nil
      end

      it 'does nothing and raises no exceptions' do
        expect do
          worker.stop
        end.not_to raise_error
      end
    end
  end

  context 'started' do
    before do
      worker.start
    end

    after do
      worker.stop
    end

    describe '#add_snapshot' do
      let(:snapshot) do
        {hello: 'world'}.freeze
      end

      let(:expected_tags) do
        {
          'debugger_version' => String,
          'host' => String,
          'language' => 'ruby',
          'library_version' => String,
          'process_id' => String,
          'runtime' => 'ruby',
          'runtime-id' => String,
          'runtime_engine' => String,
          'runtime_platform' => String,
          'runtime_version' => String,
        }
      end

      it 'sends the snapshot' do
        expect(worker.send(:snapshot_queue)).to be_empty

        expect(input_transport).to receive(:send_input).once do |snapshots, tags|
          expect(snapshots).to eq([snapshot])
          expect(tags).to match(expected_tags)
        end

        worker.add_snapshot(snapshot)

        worker.flush

        expect(worker.send(:snapshot_queue)).to eq([])
      end

      context 'when three snapshots are added in quick succession' do
        it 'sends two batches' do
          expect(worker.send(:snapshot_queue)).to be_empty

          expect(input_transport).to receive(:send_input).once do |snapshots, tags|
            expect(snapshots).to eq([snapshot])
            expect(tags).to match(expected_tags)
          end

          worker.add_snapshot(snapshot)
          sleep 0.1
          worker.add_snapshot(snapshot)
          sleep 0.1
          worker.add_snapshot(snapshot)
          sleep(0.1)

          # At this point the first snapshot should have been sent,
          # with the remaining two in the queue
          expect(worker.send(:snapshot_queue)).to eq([snapshot, snapshot])

          expect(input_transport).to receive(:send_input).once do |snapshots, tags|
            expect(snapshots).to eq([snapshot, snapshot])
            expect(tags).to match(expected_tags)
          end

          worker.flush
          expect(worker.send(:snapshot_queue)).to eq([])
        end
      end

      context 'when sending snapshot fails' do
        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

        it 'reports exception to telemetry' do
          allow(logger).to receive(:debug)
          expect(input_transport).to receive(:send_input).and_raise(StandardError, "network error")

          expect(telemetry).to receive(:report) do |exc, description:|
            expect(exc).to be_a(StandardError)
            expect(exc.message).to eq("network error")
            expect(description).to eq("Error sending snapshot")
          end

          worker.add_snapshot(snapshot)
          worker.flush

          # Queue should be cleared even after error
          expect(worker.send(:snapshot_queue)).to eq([])
        end
      end
    end

    describe '#add_status' do
      let(:status) do
        {status: 'received'}.freeze
      end

      context 'when sending status fails' do
        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

        it 'reports exception to telemetry' do
          allow(logger).to receive(:debug)
          expect(diagnostics_transport).to receive(:send_diagnostics).and_raise(StandardError, "network error")

          expect(telemetry).to receive(:report) do |exc, description:|
            expect(exc).to be_a(StandardError)
            expect(exc.message).to eq("network error")
            expect(description).to eq("Error sending status")
          end

          worker.add_status(status)
          worker.flush

          # Queue should be cleared even after error
          expect(worker.send(:status_queue)).to eq([])
        end
      end
    end

    context 'when JSON encoding fails' do
      let(:snapshot) do
        {
          debugger: {
            snapshot: {
              probe: {
                id: 'test-probe-id',
              },
              captures: {},
            },
          },
        }
      end

      let(:probe) do
        probe = instance_double(Datadog::DI::Probe,
          id: 'test-probe-id',
          type: 'log',
          location: 'test.rb:42',)
        # Allow disable! to be called with any argument
        allow(probe).to receive(:disable!)
        probe
      end

      let(:probe_repository) do
        repo = instance_double(Datadog::DI::ProbeRepository)
        allow(repo).to receive(:find_installed).with('test-probe-id').and_return(probe)
        repo
      end

      let(:status_received) { [] }

      let(:probe_notification_builder) do
        builder = instance_double(Datadog::DI::ProbeNotificationBuilder)
        allow(builder).to receive(:send).with(:build_status, anything, hash_including(:message, :status, :exception)).and_return({status: 'ERROR'})
        builder
      end

      let(:worker_with_di) do
        described_class.new(
          settings, logger,
          agent_settings: agent_settings,
          telemetry: telemetry,
          probe_repository: probe_repository,
          probe_notification_builder: probe_notification_builder,
        )
      end

      before do
        # Allow debug logging
        allow(logger).to receive(:debug)

        # Stub transport to raise JSON::GeneratorError
        allow(input_transport).to receive(:send_input) do
          raise JSON::GeneratorError.new('"\x80" from ASCII-8BIT to UTF-8')
        end

        # Allow the status to be sent
        allow(diagnostics_transport).to receive(:send_diagnostics)

        worker_with_di.start
      end

      after do
        worker_with_di.stop
      end

      it 'looks up the probe and disables it' do
        expect(probe_repository).to receive(:find_installed).with('test-probe-id').and_return(probe)
        expect(probe).to receive(:disable!).with(no_args)

        worker_with_di.add_snapshot(snapshot)
        worker_with_di.flush

        # Wait for error handling to complete
        sleep 0.2
      end

      it 'builds and sends ERROR status' do
        expect(probe_notification_builder).to receive(:send).with(:build_status, probe, hash_including(
          message: /JSON encoding failed/,
          status: 'ERROR',
        )).and_return({status: 'ERROR'})

        worker_with_di.add_snapshot(snapshot)
        worker_with_di.flush

        # Wait for error handling to complete
        sleep 0.2
      end

      it 'logs the error' do
        expect(logger).to receive(:debug).at_least(:once)

        worker_with_di.add_snapshot(snapshot)
        worker_with_di.flush

        sleep 0.2
      end
    end
  end
end
