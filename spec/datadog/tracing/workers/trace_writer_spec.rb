require 'spec_helper'

require 'datadog/core/workers/async'
require 'datadog/core/workers/polling'
require 'datadog/core/workers/queue'
require 'datadog/tracing/buffer'
require 'datadog/tracing/pipeline'
require 'datadog/tracing/workers/trace_writer'
require 'ddtrace/transport/http'
require 'ddtrace/transport/http/client'
require 'ddtrace/transport/http/response'
require 'ddtrace/transport/response'

RSpec.describe Datadog::Tracing::Workers::TraceWriter do
  subject(:writer) { described_class.new(options) }

  let(:options) { {} }

  describe '#initialize' do
    let(:transport) { instance_double(Datadog::Transport::HTTP::Client) }

    context 'given :transport' do
      let(:options) { { transport: transport } }

      it { expect(writer.transport).to be transport }
    end

    context 'given :transport_options' do
      let(:options) { { transport_options: transport_options } }

      let(:transport_options) { { example_transport_option: true } }

      before do
        expect(Datadog::Transport::HTTP).to receive(:default)
          .with(transport_options)
          .and_return(transport)
      end

      it { expect(writer.transport).to be transport }
    end

    context 'given :agent_settings' do
      let(:options) { { agent_settings: agent_settings } }
      let(:agent_settings) { double('AgentSettings') }

      it 'configures a transport with the agent_settings' do
        expect(Datadog::Transport::HTTP).to receive(:default).with(agent_settings: agent_settings).and_return(transport)

        expect(writer.transport).to be transport
      end

      context 'and also :transport_options' do
        let(:options) { { **super(), transport_options: transport_options } }

        let(:transport_options) { { example_transport_option: true } }

        before do
          expect(Datadog::Transport::HTTP).to receive(:default)
            .with(agent_settings: agent_settings, example_transport_option: true)
            .and_return(transport)
        end

        it { expect(writer.transport).to be transport }
      end
    end
  end

  describe '#write' do
    subject(:write) { writer.write(trace) }

    let(:trace) { double('trace') }
    let(:response) { instance_double(Datadog::Transport::Response) }

    before do
      expect(writer).to receive(:write_traces)
        .with([trace])
        .and_return(response)
    end

    it { is_expected.to be response }
  end

  describe '#perform' do
    subject(:perform) { writer.perform(traces) }

    let(:traces) { double('traces') }
    let(:response) { instance_double(Datadog::Transport::Response) }

    before do
      expect(writer).to receive(:write_traces)
        .with(traces)
        .and_return(response)
    end

    it { is_expected.to be response }
  end

  describe '#write_traces' do
    subject(:write_traces) { writer.write_traces(traces) }

    let(:traces) { double('traces') }
    let(:processed_traces) { double('processed traces') }
    let(:response) { instance_double(Datadog::Transport::Response) }

    before do
      expect(writer).to receive(:process_traces)
        .with(traces)
        .and_return(processed_traces)

      expect(writer).to receive(:flush_traces)
        .with(processed_traces)
        .and_return(response)
    end

    it { is_expected.to be response }
  end

  describe '#process_traces' do
    subject(:process_traces) { writer.process_traces(traces) }

    let(:traces) { double('traces') }
    let(:processed_traces) { double('processed traces') }

    it do
      expect(Datadog::Tracing::Pipeline).to receive(:process!)
        .with(traces)
        .and_return(processed_traces)

      is_expected.to be processed_traces
    end
  end

  describe '#flush_traces' do
    subject(:flush_traces) { writer.flush_traces(traces) }

    let(:traces) { double('traces') }
    let(:response) { instance_double(Datadog::Transport::Response) }

    before do
      expect(writer.transport).to receive(:send_traces)
        .with(traces)
        .and_return(response)

      expect(writer.flush_completed).to receive(:publish)
        .with(response)
    end

    it { is_expected.to be(response) }
  end

  describe '#flush_completed' do
    subject(:flush_completed) { writer.flush_completed }

    it { is_expected.to be_a_kind_of(described_class::FlushCompleted) }
  end

  describe described_class::FlushCompleted do
    subject(:event) { described_class.new }

    describe '#name' do
      subject(:name) { event.name }

      it { is_expected.to be :flush_completed }
    end
  end
end

RSpec.describe Datadog::Tracing::Workers::AsyncTraceWriter do
  subject(:writer) { described_class.new(options) }

  let(:options) { {} }

  after { writer.stop(true, 0) }

  it { expect(writer).to be_a_kind_of(Datadog::Core::Workers::Queue) }
  it { expect(writer).to be_a_kind_of(Datadog::Core::Workers::Polling) }

  describe '#initialize' do
    context 'defaults' do
      it do
        is_expected.to have_attributes(
          enabled?: true,
          fork_policy: Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART,
          buffer: kind_of(Datadog::Tracing::TraceBuffer)
        )
      end
    end

    context 'given :enabled' do
      let(:options) { { enabled: enabled } }

      context 'as false' do
        let(:enabled) { false }

        it { expect(writer.enabled?).to be false }
      end

      context 'as true' do
        let(:enabled) { true }

        it { expect(writer.enabled?).to be true }
      end

      context 'as nil' do
        let(:enabled) { nil }

        it { expect(writer.enabled?).to be false }
      end
    end

    context 'given :fork_policy' do
      let(:options) { { fork_policy: fork_policy } }

      context "as #{Datadog::Core::Workers::Async::Thread::FORK_POLICY_STOP}" do
        let(:fork_policy) { Datadog::Core::Workers::Async::Thread::FORK_POLICY_STOP }

        it { expect(writer.fork_policy).to be Datadog::Core::Workers::Async::Thread::FORK_POLICY_STOP }
      end

      context "as #{described_class::FORK_POLICY_ASYNC}" do
        let(:fork_policy) { described_class::FORK_POLICY_ASYNC }

        it { expect(writer.fork_policy).to be Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART }
      end

      context "as #{described_class::FORK_POLICY_SYNC}" do
        let(:fork_policy) { described_class::FORK_POLICY_SYNC }

        it { expect(writer.fork_policy).to be Datadog::Core::Workers::Async::Thread::FORK_POLICY_STOP }
      end
    end

    context 'given :interval' do
      let(:options) { { interval: interval } }
      let(:interval) { double('interval') }

      it { expect(writer.loop_base_interval).to be interval }
    end

    context 'given :back_off_ratio' do
      let(:options) { { back_off_ratio: back_off_ratio } }
      let(:back_off_ratio) { double('back_off_ratio') }

      it { expect(writer.loop_back_off_ratio).to be back_off_ratio }
    end

    context 'given :back_off_max' do
      let(:options) { { back_off_max: back_off_max } }
      let(:back_off_max) { double('back_off_max') }

      it { expect(writer.loop_back_off_max).to be back_off_max }
    end

    context 'given :buffer_size' do
      let(:options) { { buffer_size: buffer_size } }
      let(:buffer_size) { double('buffer_size') }
      let(:buffer) { instance_double(Datadog::Tracing::TraceBuffer) }

      before do
        expect(Datadog::Tracing::TraceBuffer).to receive(:new)
          .with(buffer_size)
          .and_return(buffer)
      end

      it { expect(writer.buffer).to be buffer }
    end
  end

  describe '#perform' do
    subject(:perform) { writer.perform }

    after { writer.stop }

    it 'starts a worker thread' do
      perform

      expect(writer.send(:worker)).to be_a_kind_of(Thread)
      expect(writer).to have_attributes(
        run_async?: true,
        running?: true,
        started?: true,
        forked?: false,
        fork_policy: :restart,
        result: nil
      )
    end
  end

  describe '#enqueue' do
    subject(:enqueue) { writer.enqueue(trace) }

    let(:trace) { double('trace') }

    before do
      allow(writer.buffer).to receive(:push)
      enqueue
    end

    it { expect(writer.buffer).to have_received(:push).with(trace) }
  end

  describe '#dequeue' do
    subject(:dequeue) { writer.dequeue }

    let(:traces) { double('traces') }

    before do
      allow(writer.buffer).to receive(:pop)
        .and_return(traces)
    end

    it { is_expected.to eq([traces]) }
  end

  describe '#stop' do
    before { skip if PlatformHelpers.jruby? } # DEV: Temporarily disabled due to flakiness

    subject(:stop) { writer.stop }

    shared_context 'shuts down the worker' do
      before do
        expect(writer.buffer).to receive(:close).at_least(:once)

        allow(writer).to receive(:join)
          .with(described_class::SHUTDOWN_TIMEOUT)
          .and_return(true)

        # Do this to prevent cleanup from breaking the test
        allow(writer).to receive(:join)
          .with(0)
          .and_return(true)
      end
    end

    context 'when the worker has not been started' do
      before do
        expect(writer.buffer).to_not receive(:close)
        allow(writer).to receive(:join)
          .with(described_class::SHUTDOWN_TIMEOUT)
          .and_return(true)
      end

      it { is_expected.to be false }
    end

    context 'when the worker has been started' do
      include_context 'shuts down the worker'

      before do
        writer.perform
        try_wait_until { writer.running? && writer.run_loop? }
      end

      it { is_expected.to be true }
    end

    context 'called multiple times with graceful stop' do
      include_context 'shuts down the worker'

      before do
        writer.perform
        try_wait_until { writer.running? && writer.run_loop? }
      end

      it do
        expect(writer.stop).to be true
        try_wait_until { !writer.running? }
        expect(writer.stop).to be false
      end
    end

    context 'given force_stop: true' do
      subject(:stop) { writer.stop(true) }

      context 'and the worker does not gracefully stop' do
        before do
          # Make it ignore graceful stops
          expect(writer.buffer).to receive(:close)
          allow(writer).to receive(:stop_loop).and_return(false)
          allow(writer).to receive(:join).and_return(nil)
        end

        context 'after the worker has been started' do
          before { writer.perform }

          it do
            is_expected.to be true

            # Give thread time to be terminated
            try_wait_until { !writer.running? }

            expect(writer.run_async?).to be false
            expect(writer.running?).to be false
          end
        end
      end
    end
  end

  describe '#work_pending?' do
    subject(:work_pending?) { writer.work_pending? }

    context 'when the buffer is empty' do
      it { is_expected.to be false }
    end

    context 'when the buffer is not empty' do
      let(:trace) { get_test_traces(1).first }

      before { writer.enqueue(trace) }

      it { is_expected.to be true }
    end
  end

  describe '#async=' do
    subject(:set_async) { writer.async = value }

    context 'given true' do
      let(:value) { true }

      it do
        is_expected.to be true
        expect(writer.async?).to be true
      end
    end

    context 'given false' do
      let(:value) { false }

      it do
        is_expected.to be false
        expect(writer.async?).to be false
      end
    end
  end

  describe '#async?' do
    subject(:async?) { writer.async? }

    context 'by default' do
      it { is_expected.to be true }
    end

    context 'when set to false' do
      before { writer.async = false }

      it do
        is_expected.to be false
      end
    end

    context 'when set to truthy' do
      before { writer.async = 1 }

      it do
        is_expected.to be false
      end
    end
  end

  describe '#fork_policy=' do
    subject(:set_fork_policy) { writer.fork_policy = value }

    context 'given FORK_POLICY_ASYNC' do
      let(:value) { described_class::FORK_POLICY_ASYNC }

      it do
        is_expected.to be value
        expect(writer.fork_policy).to eq(Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART)
      end
    end

    context 'given FORK_POLICY_SYNC' do
      let(:value) { described_class::FORK_POLICY_SYNC }

      it do
        is_expected.to be value
        expect(writer.fork_policy).to eq(Datadog::Core::Workers::Async::Thread::FORK_POLICY_STOP)
      end
    end
  end

  describe '#after_fork' do
    subject(:after_fork) { writer.after_fork }

    it { expect { after_fork }.to(change { writer.buffer }) }

    context 'when fork_policy is' do
      before { writer.fork_policy = fork_policy }

      context 'FORK_POLICY_ASYNC' do
        let(:fork_policy) { described_class::FORK_POLICY_ASYNC }

        it do
          expect { after_fork }.to_not(change { writer.async? })
        end
      end

      context 'FORK_POLICY_SYNC' do
        let(:fork_policy) { described_class::FORK_POLICY_SYNC }

        it do
          expect { after_fork }.to change { writer.async? }.from(true).to(false)
        end
      end
    end
  end

  describe '#write' do
    subject(:write) { writer.write(trace) }

    let(:trace) { double('trace') }

    context 'when #async?' do
      before { expect(writer.async?).to be true }

      context 'is true' do
        it 'starts a worker thread & queues the trace' do
          expect(writer.buffer).to receive(:push)
            .with(trace)

          expect { write }.to change { writer.running? }
            .from(false)
            .to(true)
        end
      end

      context 'is false' do
        before { allow(writer).to receive(:async?).and_return(false) }

        it 'writes the trace synchronously' do
          expect(writer.buffer).to_not receive(:push)
          expect(writer).to receive(:write_traces)
            .with([trace])
          write
        end
      end
    end
  end

  describe 'integration tests' do
    let(:options) { { transport: transport, fork_policy: fork_policy } }
    let(:transport) { Datadog::Transport::HTTP.default { |t| t.adapter :test, output } }
    let(:output) { [] }

    describe 'forking' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      context 'when the process forks and a trace is written' do
        let(:traces) { get_test_traces(3) }

        before do
          allow(writer).to receive(:after_fork)
            .and_call_original
          allow(writer.transport).to receive(:send_traces)
            .and_call_original
        end

        after { expect(writer.stop).to be_truthy }

        context 'with :sync fork policy' do
          let(:fork_policy) { :sync }

          it 'does not drop any traces' do
            # Start writer in main process
            writer.perform

            expect_in_fork do
              traces.each do |trace|
                expect(writer.write(trace)).to all(be_a(Datadog::Transport::HTTP::Response))
              end

              expect(writer).to have_received(:after_fork).once

              traces.each do |trace|
                expect(writer.transport).to have_received(:send_traces)
                  .with([trace])
              end

              expect(writer.buffer).to be_empty
            end
          end
        end

        context 'with :async fork policy' do
          let(:fork_policy) { :async }
          let(:flushed_traces) { [] }

          it 'does not drop any traces' do
            # Start writer in main process
            writer.perform

            expect_in_fork do
              # Queue up traces, wait for worker to process them.
              traces.each { |trace| writer.write(trace) }
              try_wait_until(seconds: 3) { !writer.work_pending? }
              writer.stop

              # Verify state of the writer
              expect(writer).to have_received(:after_fork).once
              expect(writer.buffer).to be_empty
              expect(writer.error?).to be false

              expect(writer.transport).to have_received(:send_traces).at_most(traces.length).times do |traces|
                flushed_traces.concat(traces)
              end

              expect(flushed_traces).to_not be_empty
              expect(flushed_traces).to have(traces.length).items
              expect(flushed_traces).to include(*traces)
            end
          end
        end
      end
    end
  end
end
