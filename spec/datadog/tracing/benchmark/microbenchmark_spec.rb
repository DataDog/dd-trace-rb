require 'spec_helper'

require_relative 'support/benchmark_helper'

RSpec.describe 'Microbenchmark' do
  # Empty benchmark to assess the overhead benchmarking tools
  # and stability of underlying hardware.
  describe 'baseline' do
    include_examples 'benchmark'

    def subject(_); end
  end

  describe Datadog::Tracing::Tracer do
    describe 'nested traces' do
      let(:name) { 'span'.freeze }
      let(:tracer) { new_tracer(writer: FauxWriter.new(call_original: false)) }
      let(:steps) { [1, 10, 100] }

      include_examples 'benchmark'

      def trace(i, total)
        tracer.trace(name) { trace(i + 1, total) unless i == total }
      end

      def subject(i)
        trace(1, i)
      end
    end
  end

  describe Datadog::Tracing::Writer do
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
        let(:buffer_size) { -1 }

        include_examples 'benchmark'
      end

      context 'with buffer full' do
        let(:buffer_size) { Datadog::Tracing::Workers::AsyncTransport::DEFAULT_BUFFER_MAX_SIZE }

        before do
          buffer_size.times { writer.write(span1) } # fill up buffer
        end

        include_examples 'benchmark'

        def reset_buffer
          # No need to reset, we actually want the buffer always full
        end
      end
    end
  end

  describe 'end-to-end' do
    include_context 'minimal agent'

    describe 'nested traces' do
      let(:name) { 'span'.freeze }
      let(:writer) { Datadog::Tracing::Writer.new(buffer_size: 1000, flush_interval: 0) }
      let(:tracer) { Datadog::Tracing::Tracer.new(writer: writer) }
      let(:steps) { [1, 10, 100] }
      let(:memory_iterations) { 1000 }
      let(:timing_runtime) { 60 }

      after { tracer.shutdown! }

      include_examples 'benchmark'

      def trace(i, total)
        tracer.trace(name) { trace(i + 1, total) unless i == total }
      end

      def subject(i)
        trace(1, i)
      end
    end
  end

  describe 'single span sampling' do
    before do
      Datadog.configure do |c|
        c.tracing.writer = FauxWriter.new(call_original: false)
      end
    end

    let(:name) { 'span'.freeze }
    let(:tracer) { Datadog::Tracing.send(:tracer) }
    let(:steps) { [1, 10, 100] }

    def subject(i)
      trace(1, i)
    end

    describe 'kept traces' do
      include_examples 'benchmark'

      def trace(i, total)
        tracer.trace(name) do |_, trace|
          trace.keep! if i == 1
          trace(i + 1, total) unless i == total
        end
      end
    end

    describe 'rejected traces' do
      include_examples 'benchmark'

      def trace(i, total)
        tracer.trace(name) do |_, trace|
          trace.reject! if i == 1
          trace(i + 1, total) unless i == total
        end
      end

      describe 'with spans kept by single span sampling' do
        before do
          Datadog.configure do |c|
            c.tracing.sampling.span_rules = json_rules
          end
        end

        let(:json_rules) { [rule].to_json }
        let(:rule) do
          {
            name: name,
            sample_rate: 1.0,
          }
        end

        include_examples 'benchmark'
      end

      describe 'with spans also rejected by single span sampling' do
        before do
          Datadog.configure do |c|
            c.tracing.sampling.span_rules = json_rules
          end
        end

        let(:json_rules) { [rule].to_json }
        let(:rule) do
          {
            name: name,
            sample_rate: 0.0,
          }
        end

        include_examples 'benchmark'
      end
    end
  end
end
