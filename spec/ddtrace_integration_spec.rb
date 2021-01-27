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

      it 'closes tracer file descriptors' do
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
        shutdown
        expect(fd_count).to eq(original_fd_count)
      end
    end
  end
end
