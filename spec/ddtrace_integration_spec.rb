RSpec.describe 'ddtrace integration', :integration do
  context 'graceful shutdown' do
    subject(:shutdown) { Datadog.shutdown! }

    let(:start_tracer) do
      Datadog.configure {}
      Datadog.tracer.trace('test.op') {}
    end

    def wait_for_tracer_sent
      try_wait_until { Datadog.tracer.writer.transport.stats.success > 0 }
    end

    context 'for threads' do
      before do
        original_thread_count
      end

      let(:original_thread_count) { thread_count }

      def thread_count
        Thread.list.count
      end

      it 'closes tracer threads' do
        start_tracer
        wait_for_tracer_sent

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
        start_tracer
        wait_for_tracer_sent

        shutdown

        expect(fd_count).to eq(original_fd_count)
      end
    end
  end
end
