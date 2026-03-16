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

  let(:default_probe_repository) do
    instance_double(Datadog::DI::ProbeRepository)
  end

  let(:default_probe_notification_builder) do
    instance_double(Datadog::DI::ProbeNotificationBuilder)
  end

  let(:worker) do
    described_class.new(
      settings, logger,
      agent_settings: agent_settings,
      telemetry: telemetry,
      probe_repository: default_probe_repository,
      probe_notification_builder: default_probe_notification_builder,
    )
  end

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

        expect(input_transport).to receive(:send_input).once do |snapshots, tags, **_kwargs|
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

          # Use Queue to wait for first send to complete (deterministic synchronization)
          first_send_done = Queue.new

          expect(input_transport).to receive(:send_input).once do |snapshots, tags, **_kwargs|
            expect(snapshots).to eq([snapshot])
            expect(tags).to match(expected_tags)
            first_send_done.push(:done)
          end

          worker.add_snapshot(snapshot)

          # Wait for the first send to complete (deterministic)
          Timeout.timeout(2) { first_send_done.pop }

          worker.add_snapshot(snapshot)
          worker.add_snapshot(snapshot)

          # At this point the first snapshot should have been sent,
          # with the remaining two in the queue
          expect(worker.send(:snapshot_queue)).to eq([snapshot, snapshot])

          expect(input_transport).to receive(:send_input).once do |snapshots, tags, **_kwargs|
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
          expect_lazy_log(logger, :debug, /failed to send snapshot.*network error/)
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
          expect_lazy_log(logger, :debug, /failed to send probe status.*network error/)
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

    describe '#handle_serialization_error' do
      let(:probe_repository) do
        instance_double(Datadog::DI::ProbeRepository)
      end

      let(:probe_notification_builder) do
        instance_double(Datadog::DI::ProbeNotificationBuilder).tap do |builder|
          allow(builder).to receive(:build_status).with(anything, hash_including(:message, :status, :exception)).and_return({status: 'ERROR'})
        end
      end

      let(:worker) do
        described_class.new(
          settings, logger,
          agent_settings: agent_settings,
          telemetry: telemetry,
          probe_repository: probe_repository,
          probe_notification_builder: probe_notification_builder,
        )
      end

      let(:probe) do
        instance_double(Datadog::DI::Probe, id: 'test-probe', type: 'log', location: 'test.rb:42')
      end

      let(:exception) { JSON::GeneratorError.new('binary data not allowed') }

      context 'when probe is found' do
        before do
          allow(probe_repository).to receive(:find_installed).with('test-probe').and_return(probe)
          allow(probe).to receive(:disable!)
          allow(diagnostics_transport).to receive(:send_diagnostics)
        end

        it 'disables the probe' do
          expect_lazy_log(logger, :debug, /disabling probe test-probe due to serialization error/)
          expect(probe).to receive(:disable!)

          worker.send(:handle_serialization_error, 'test-probe', exception)
        end

        it 'sends ERROR status' do
          expect_lazy_log(logger, :debug, /disabling probe test-probe/)
          allow(probe).to receive(:disable!)

          expect(probe_notification_builder).to receive(:build_status).with(probe, hash_including(
            message: /JSON encoding failed/,
            status: 'ERROR',
          ))

          worker.send(:handle_serialization_error, 'test-probe', exception)
        end

        it 'queues the status for sending' do
          expect_lazy_log(logger, :debug, /disabling probe test-probe/)
          allow(probe).to receive(:disable!)

          worker.send(:handle_serialization_error, 'test-probe', exception)

          expect(worker.send(:status_queue)).not_to be_empty
        end

        it 'logs the serialization error with probe ID and exception details' do
          expect_lazy_log(logger, :debug, /disabling probe test-probe due to serialization error: JSON::GeneratorError: binary data not allowed/)

          worker.send(:handle_serialization_error, 'test-probe', exception)
        end
      end

      context 'when probe is not found' do
        before do
          allow(probe_repository).to receive(:find_installed).with('unknown-probe').and_return(nil)
        end

        it 'does nothing' do
          expect(probe_notification_builder).not_to receive(:build_status)

          worker.send(:handle_serialization_error, 'unknown-probe', exception)
        end
      end
    end

    context 'serialization error — end-to-end through real transport' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 'bad-probe', type: :log, file: 'test.rb', line_no: 1)
      end

      let(:real_probe_repository) do
        Datadog::DI::ProbeRepository.new
      end

      let(:error_probe_notification_builder) do
        instance_double(Datadog::DI::ProbeNotificationBuilder).tap do |builder|
          allow(builder).to receive(:build_status)
            .with(anything, hash_including(:message, :status, :exception))
            .and_return({status: 'ERROR'})
        end
      end

      # Override input_transport so the outer before block (which does
      # allow(Transport::HTTP.input).and_return(input_transport)) picks up the
      # real transport. This ensures the full send_input serialization path runs.
      let(:input_transport) do
        Datadog::DI::Transport::HTTP.input(
          agent_settings: agent_settings,
          logger: logger,
          telemetry: nil,
        ).tap do |transport|
          allow(transport).to receive(:send_input_chunk)
        end
      end

      let(:worker) do
        described_class.new(
          settings, logger,
          agent_settings: agent_settings,
          telemetry: nil,
          probe_repository: real_probe_repository,
          probe_notification_builder: error_probe_notification_builder,
        )
      end

      let(:bad_snapshot) do
        {
          debugger: {
            snapshot: {
              probe: {id: 'bad-probe'},
              captures: {locals: {data: "\x80".force_encoding('ASCII-8BIT')}},
            },
          },
        }
      end

      before do
        real_probe_repository.add_installed(probe)
        allow(diagnostics_transport).to receive(:send_diagnostics)
        allow(logger).to receive(:debug)
      end

      it 'disables the probe when its snapshot cannot be JSON-encoded' do
        worker.add_snapshot(bad_snapshot)
        worker.flush

        expect(probe.enabled?).to be false
      end

      it 'sends ERROR status for the affected probe' do
        expect(error_probe_notification_builder).to receive(:build_status).with(
          probe,
          hash_including(status: 'ERROR', message: /JSON encoding failed/),
        ).and_return({status: 'ERROR'})

        worker.add_snapshot(bad_snapshot)
        worker.flush
      end
    end
  end
end
