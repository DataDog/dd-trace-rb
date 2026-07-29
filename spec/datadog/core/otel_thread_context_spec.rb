require "spec_helper"
require "support/otel_thread_context_test_helpers"

require "etc"
require "datadog/core/otel_thread_context"

RSpec.describe Datadog::Core::OTelThreadContext, if: PlatformHelpers.linux? do
  describe ".set" do
    before(:all) do
      described_class.singleton_class.include(OTelThreadContextTestHelpers)
      described_class.enable!
    end

    before do
      fail("libdatadog built without otel-thread-ctx") unless described_class.supported?
    end

    around(:each) do |example|
      Thread.new do
        example.run
      end.join
    end

    it "sets the thread context" do
      trace_id = 0xf0e1_d2c3_b4a5_9687_7869_5a4b_3c2d_1e0f
      span_id = 0xfedc_ba98_7654_3210
      local_root_span_id = 0xefcd_ab89_6745_2301

      described_class.set(trace_id: trace_id, span_id: span_id, local_root_span_id: local_root_span_id)

      expect(described_class.read).to include(
        trace_id: trace_id, span_id: span_id, local_root_span_id: local_root_span_id
      )
    end

    it "updates the thread context on fiber switch" do
      described_class.set(trace_id: 1, span_id: 2, local_root_span_id: 3)

      fiber = Fiber.new do
        described_class.set(trace_id: 11, span_id: 12, local_root_span_id: 13)

        Fiber.yield

        described_class.read
      end

      fiber.resume
      expect(described_class.read).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)

      fiber_context = fiber.resume
      expect(fiber_context).to include(trace_id: 11, span_id: 12, local_root_span_id: 13)

      expect(described_class.read).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)
    end

    it "updates the thread context when switching between fibers" do
      fiber_a = Fiber.new do
        described_class.set(trace_id: 100, span_id: 101, local_root_span_id: 102)
        Fiber.yield
        described_class.read
      end

      fiber_b = Fiber.new do
        described_class.set(trace_id: 200, span_id: 201, local_root_span_id: 202)
        Fiber.yield
        described_class.read
      end

      fiber_a.resume
      fiber_b.resume

      expect(fiber_a.resume).to include(trace_id: 100, span_id: 101, local_root_span_id: 102)
      expect(fiber_b.resume).to include(trace_id: 200, span_id: 201, local_root_span_id: 202)

      expect(described_class.read).to include(trace_id: 0, span_id: 0, local_root_span_id: 0)
    end

    # This example is for the Valgrind memcheck run.
    it "releases the thread context when a Thread exits", if: RUBY_VERSION >= "3.3" do
      Thread.new do
        described_class.set(trace_id: 1, span_id: 2, local_root_span_id: 3)
      end.join

      signal_queue = Queue.new
      killed = Thread.new do
        described_class.set(trace_id: 11, span_id: 12, local_root_span_id: 13)
        signal_queue << true
        Queue.new.pop
      end

      signal_queue.pop # ensure we set the thread context before we kill the thread
      killed.kill
      killed.join

      failed = Thread.new do
        Thread.current.report_on_exception = false
        described_class.set(trace_id: 21, span_id: 22, local_root_span_id: 23)
        raise StandardError
      end

      expect { failed.join }.to raise_error(StandardError)

      expect(described_class.read).to include(trace_id: 0, span_id: 0, local_root_span_id: 0)
    end

    context "inside a non-main Ractor", if: RUBY_VERSION >= "3.3", memcheck_valgrind_skip: true do
      it "keeps thread context correct under the M:N scheduler" do
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

      it "updates the thread context on fiber switch" do
        outer, inner = Ractor.new do
          Datadog::Core::OTelThreadContext.set(trace_id: 1, span_id: 2, local_root_span_id: 3)

          fiber = Fiber.new do
            Datadog::Core::OTelThreadContext.set(trace_id: 11, span_id: 12, local_root_span_id: 13)
            Fiber.yield
            Datadog::Core::OTelThreadContext.read
          end

          fiber.resume
          outer_after_yield = Datadog::Core::OTelThreadContext.read
          inner_after_resume = fiber.resume

          [outer_after_yield, inner_after_resume]
        end.take

        expect(outer).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)
        expect(inner).to include(trace_id: 11, span_id: 12, local_root_span_id: 13)
      end
    end
  end
end
