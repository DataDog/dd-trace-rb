require "spec_helper"

require "etc"
require "datadog/core/otel_thread_context"

RSpec.describe Datadog::Core::OTelThreadContext, if: PlatformHelpers.linux? do
  describe '.set' do
    before do
      described_class.enable!
    end

    around(:each) do |example|
      Thread.new do
        example.run
      end.join
    end

    it 'sets the thread context' do
      described_class.set(trace_id: 1, span_id: 2, local_root_span_id: 3)
      expect(described_class.read).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)
    end

    it 'updates the thread context on fiber switch' do
      described_class.set(trace_id: 1, span_id: 2, local_root_span_id: 3)

      f = Fiber.new do
        described_class.set(trace_id: 11, span_id: 12, local_root_span_id: 13)

        Fiber.yield

        expect(described_class.read).to include(trace_id: 11, span_id: 12, local_root_span_id: 13)
      end

      f.resume
      expect(described_class.read).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)

      f.resume
      expect(described_class.read).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)
    end

    it 'updates the thread context when switching between fibers' do
      fiber_a = Fiber.new do
        described_class.set(trace_id: 100, span_id: 101, local_root_span_id: 102)
        Fiber.yield
        expect(described_class.read).to include(trace_id: 100, span_id: 101, local_root_span_id: 102)
      end

      fiber_b = Fiber.new do
        described_class.set(trace_id: 200, span_id: 201, local_root_span_id: 202)
        Fiber.yield
        expect(described_class.read).to include(trace_id: 200, span_id: 201, local_root_span_id: 202)
      end

      fiber_a.resume
      fiber_b.resume
      fiber_a.resume
      fiber_b.resume

      expect(described_class.read).to include(trace_id: 0, span_id: 0, local_root_span_id: 0)
    end

    it 'resets the thread context when the Thread dies' do
      Thread.new do
        described_class.set(trace_id: 1, span_id: 2, local_root_span_id: 3)
      end.join

      expect(described_class.read).to include(trace_id: 0, span_id: 0, local_root_span_id: 0)
    end

    it 'keeps thread context correct under the M:N scheduler', if: RUBY_VERSION >= '3.3' do
      thread_count = Etc.nprocessors * 4 + 1

      # M:N is disabled on the main Ractor by default
      results = Ractor.new(thread_count) do |count|
        Array.new(count) do |i|
          Thread.new do
            Datadog::Core::OTelThreadContext.set(trace_id: i, span_id: i + 1, local_root_span_id: i + 2)
            Thread.pass
            Datadog::Core::OTelThreadContext.read&.fetch(:trace_id)
          end
        end.map(&:value)
      end.take

      expect(results).to match_array((0..(thread_count - 1)).to_a)
    end
  end
end
