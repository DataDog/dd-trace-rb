require 'spec_helper'

RSpec.describe 'ddtrace integration' do
  context 'graceful shutdown' do
    subject(:shutdown) { Datadog.shutdown! }

    let(:start_tracer) do
      Datadog.configure {}
      Datadog.tracer.trace('test.op') {}
    end

    context 'for threads' do
      before do
        original_thread_count
        start_tracer
      end

      let(:original_thread_count) { thread_count }

      def thread_count
        Thread.list.count
      end

      it 'closes tracer threads' do
        try_wait_until { thread_count > original_thread_count }

        shutdown

        expect(thread_count).to eq(original_thread_count)
      end
    end

    context 'for file descriptors' do
      before do
        original_fd_count
        start_tracer
      end

      let(:original_fd_count) { fd_count }

      def fd_count
        Dir['/dev/fd/*'].size
      end

      it 'closes tracer file descriptors' do
        # There's currently a short period of time when we open
        # a socket to send traces to the agent.
        try_wait_until(attempts: 5000, backoff: 0.001) { fd_count > original_fd_count }

        shutdown

        expect(fd_count).to eq(original_fd_count)
      end
    end
  end
end
