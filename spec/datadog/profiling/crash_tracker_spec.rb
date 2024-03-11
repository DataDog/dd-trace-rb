require 'datadog/profiling/spec_helper'
require 'datadog/profiling/crash_tracker'

require 'webrick'

RSpec.describe Datadog::Profiling::CrashTracker do
  before { skip_if_profiling_not_supported(self) }

  let(:exporter_configuration) { [:agent, 'http://localhost:6006'] }

  subject(:crash_tracker) do
    described_class.new(
      exporter_configuration: exporter_configuration,
      tags: { 'tag1' => 'value1', 'tag2' => 'value2' },
    )
  end

  describe '#start' do
    subject(:start) { crash_tracker.start }

    context 'when _native_start_or_update_on_fork raises an exception' do
      it 'logs the exception' do
        expect(described_class).to receive(:_native_start_or_update_on_fork) { raise 'Test failure' }
        expect(Datadog.logger).to receive(:error).with(/Failed to start crash tracking: Test failure/)

        start
      end
    end

    context 'when path_to_crashtracking_receiver_binary is nil' do
      subject(:crash_tracker) do
        described_class.new(
          exporter_configuration: exporter_configuration,
          tags: { 'tag1' => 'value1', 'tag2' => 'value2' },
          path_to_crashtracking_receiver_binary: nil
        )
      end

      it 'logs a warning' do
        expect(Datadog.logger).to receive(:warn).with(/no path_to_crashtracking_receiver_binary was found/)

        start
      end
    end

    it 'starts the crash tracker' do
      start

      expect(`pgrep -f libdatadog-crashtracking-receiver`).to_not be_empty

      crash_tracker.stop
    end

    context 'when calling start multiple times in a row' do
      it 'only starts the crash tracker once' do
        3.times { crash_tracker.start }

        expect(`pgrep -f libdatadog-crashtracking-receiver`.lines.size).to be 1

        crash_tracker.stop
      end
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { crash_tracker.reset_after_fork }

    context 'when called in a fork' do
      before { crash_tracker.start }
      after { crash_tracker.stop }

      it 'starts a second crash tracker for the fork' do
        expect_in_fork do
          crash_tracker.reset_after_fork

          expect(`pgrep -f libdatadog-crashtracking-receiver`.lines.size).to be 2

          crash_tracker.stop

          expect(`pgrep -f libdatadog-crashtracking-receiver`.lines.size).to be 1
        end
      end
    end
  end

  describe '#stop' do
    subject(:stop) { crash_tracker.stop }

    context 'when _native_stop_crashtracker raises an exception' do
      it 'logs the exception' do
        expect(described_class).to receive(:_native_stop) { raise 'Test failure' }
        expect(Datadog.logger).to receive(:error).with(/Failed to stop crash tracking: Test failure/)

        stop
      end
    end

    it 'stops the crash tracker' do
      crash_tracker.start

      stop

      expect(`pgrep -f libdatadog-crashtracking-receiver`).to be_empty
    end
  end

  context 'integration testing' do
    shared_context 'HTTP server' do
      let(:server) do
        WEBrick::HTTPServer.new(
          Port: port,
          Logger: log,
          AccessLog: access_log,
          StartCallback: -> { init_signal.push(1) }
        )
      end
      let(:hostname) { '127.0.0.1' }
      let(:port) { 6006 }
      let(:log) { WEBrick::Log.new(StringIO.new, WEBrick::Log::WARN) }
      let(:access_log_buffer) { StringIO.new }
      let(:access_log) { [[access_log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
      let(:server_proc) do
        proc do |req, res|
          messages << req.tap { req.body } # Read body, store message before socket closes.
          res.body = '{}'
        end
      end
      let(:init_signal) { Queue.new }

      let(:messages) { [] }

      before do
        server.mount_proc('/', &server_proc)
        @server_thread = Thread.new { server.start }
        init_signal.pop
      end

      after do
        unless RSpec.current_example.skipped?
          # When the test is skipped, server has not been initialized and @server_thread would be nil; thus we only
          # want to touch them when the test actually run, otherwise we would cause the server to start (incorrectly)
          # and join to be called on a nil @server_thread
          server.shutdown
          @server_thread.join
        end
      end
    end

    include_context 'HTTP server'

    let(:request) { messages.first }

    let(:hostname) { '127.0.0.1' }
    let(:port) { '6006' }

    it 'reports crashes via http' do
      fork_expectations = proc do |status:, stdout:, stderr:|
        expect(Signal.signame(status.termsig)).to eq('SEGV').or eq('ABRT')
        expect(stderr).to include('[BUG] Segmentation fault')
      end

      expect_in_fork(fork_expectations: fork_expectations) do
        crash_tracker.start

        Process.kill('SEGV', Process.pid)
        # TODO: For some reason, the crash tracker is not handing control back to the Ruby SEGV handler the first time
        Process.kill('SEGV', Process.pid)
      end

      boundary = request['content-type'][%r{^multipart/form-data; boundary=(.+)}, 1]
      body = WEBrick::HTTPUtils.parse_form_data(StringIO.new(request.body), boundary)
      expect(body.fetch('crash-info.json')).to_not be nil
    end
  end
end
