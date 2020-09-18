require 'spec_helper'

require_relative 'support/benchmark_helper'

RSpec.describe 'Microbenchmark' do
  # Empty benchmark to assess the overhead benchmarking tools
  # and stability of underlying hardware.
  describe 'baseline' do
    include_examples 'benchmark'

    def subject(_); end
  end

  describe Datadog::Tracer do
    describe 'nested traces' do
      include_examples 'benchmark'

      let(:steps) { [1, 10, 100] }

      let(:tracer) { new_tracer(writer: FauxWriter.new(call_original: false)) }
      let(:name) { 'span'.freeze }

      def trace(i, total)
        tracer.trace(name) { trace(i + 1, total) unless i == total }
      end

      def subject(i)
        trace(1, i)
      end
    end
  end

  describe Datadog::Writer do
    describe '#write' do
      let(:steps) { [1, 100] }
      let(:memory_iterations) { 100 }

      let(:writer) { described_class.new(transport: FauxTransport.new, buffer_size: buffer_size, flush_interval: 1e9) }
      let(:span1) { get_test_traces(1).flatten }
      let(:span100) { get_test_traces(100).flatten }
      let(:span) { { 1 => span1, 100 => span100 } }

      before do
        writer.start
      end

      def subject(i)
        reset_buffer # Ensure buffer is in a predictable state
        writer.write(span[i])
      end

      def reset_buffer
        # Keep in mind the overhead created by this method when analysing results
        writer.worker.trace_buffer.instance_variable_set(:@traces, [])
      end

      context 'with space in buffer' do
        include_examples 'benchmark'

        let(:buffer_size) { -1 }
      end

      context 'with buffer full' do
        include_examples 'benchmark'

        let(:buffer_size) { Datadog::Workers::AsyncTransport::DEFAULT_BUFFER_MAX_SIZE }

        before do
          buffer_size.times { writer.write(span1) } # fill up buffer
        end

        def reset_buffer
          # No need to reset, we actually want the buffer always full
        end
      end
    end
  end

  describe 'end-to-end' do
    include_context 'minimal agent'

    describe 'nested traces' do
      include_examples 'benchmark'

      let(:timing_runtime) { 60 }
      let(:memory_iterations) { 1000 }

      let(:steps) { [1, 10, 100] }

      let(:tracer) { Datadog::Tracer.new }
      after { tracer.shutdown! }

      let(:name) { 'span'.freeze }

      def trace(i, total)
        tracer.trace(name) { trace(i + 1, total) unless i == total }
      end

      def subject(i)
        trace(1, i)
      end
    end
  end
end
