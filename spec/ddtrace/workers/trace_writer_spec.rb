require 'spec_helper'

require 'ddtrace'
require 'ddtrace/workers/trace_writer'

RSpec.describe Datadog::Workers::TraceWriter do
  subject(:writer) { described_class.new(options) }
  let(:options) { {} }

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

    before do
      expect(Datadog::Pipeline).to receive(:process!)
        .with(traces)
        .and_return(processed_traces)
    end

    context 'when \'report_hostname\'' do
      context 'is enabled' do
        before do
          allow(Datadog.configuration).to receive(:report_hostname)
            .and_return(true)

          expect(writer).to receive(:inject_hostname!)
            .with(processed_traces)
        end

        it { is_expected.to be(processed_traces) }
      end

      context 'is not enabled' do
        before do
          allow(Datadog.configuration).to receive(:report_hostname)
            .and_return(false)
        end

        it { is_expected.to be(processed_traces) }
      end
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

  describe '#inject_hostname!' do
    subject(:inject_hostname!) { writer.inject_hostname!(traces) }
    let(:traces) { get_test_traces(2) }

    context 'when hostname' do
      before do
        allow(Datadog::Runtime::Socket).to receive(:hostname)
          .and_return(hostname)
      end

      context 'is available' do
        let(:hostname) { 'localhost' }

        it 'sets the hostname on the first span of each trace' do
          inject_hostname!

          traces.each do |trace|
            expect(trace.first.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to eq(hostname)
          end
        end
      end

      context 'is not available' do
        let(:hostname) { nil }

        it 'hoes not set the hostname on any of the traces' do
          inject_hostname!

          traces.each do |trace|
            expect(trace.first.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to be nil
          end
        end
      end
    end
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

RSpec.describe Datadog::Workers::AsyncTraceWriter do
  subject(:writer) { described_class.new(options) }
  let(:options) { {} }

  describe '#perform' do
    subject(:perform) { writer.perform }
    after { writer.stop }

    it 'starts a worker thread' do
      is_expected.to be_a_kind_of(Thread)
      expect(writer).to have_attributes(
        run_async?: true,
        running?: true,
        unstarted?: false,
        forked?: false,
        fork_policy: :restart,
        result: nil
      )
    end
  end

  describe '#write' do
    subject(:write) { writer.write(trace) }
    let(:trace) { double('trace') }

    context 'when in async mode' do
      before { allow(writer).to receive(:async?).and_return true }

      context 'and given a trace' do
        before do
          allow(writer.buffer).to receive(:push)
          write
        end

        it { expect(writer.buffer).to have_received(:push).with(trace) }
      end
    end

    context 'when not in async mode' do
      before { allow(writer).to receive(:async?).and_return false }

      context 'and given a trace' do
        before do
          allow(writer).to receive(:write_traces)
          write
        end

        it { expect(writer).to have_received(:write_traces).with([trace]) }
      end
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
    subject(:stop) { writer.stop }

    shared_context 'shuts down the worker' do
      before do
        expect(writer.buffer).to receive(:close)
        allow(writer).to receive(:join)
          .with(described_class::SHUTDOWN_TIMEOUT)
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
        expect(writer.fork_policy).to eq(Datadog::Workers::Async::Thread::FORK_POLICY_RESTART)
      end
    end

    context 'given FORK_POLICY_SYNC' do
      let(:value) { described_class::FORK_POLICY_SYNC }

      it do
        is_expected.to be value
        expect(writer.fork_policy).to eq(Datadog::Workers::Async::Thread::FORK_POLICY_STOP)
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
      context 'when the process forks and a trace is written' do
        let(:traces) { get_test_traces(3) }

        before do
          allow(writer).to receive(:after_fork)
            .and_call_original
          allow(writer.transport).to receive(:send_traces)
            .and_call_original
        end

        after { writer.stop }

        context 'with :sync fork policy' do
          let(:fork_policy) { :sync }

          it 'does not drop any traces' do
            # Start writer in main process
            writer.perform

            expect_in_fork do
              traces.each do |trace|
                expect(writer.write(trace)).to be_a_kind_of(Datadog::Transport::HTTP::Response)
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
              try_wait_until(attempts: 30) { !writer.work_pending? }

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
