require "spec_helper"

require "datadog/tracing/otel_thread_context"

RSpec.describe Datadog::Tracing::OTelThreadContext, if: PlatformHelpers.linux? do
  around(:each) do |example|
    Thread.new do
      example.run
    end.join
  end

  describe ".set" do
    def decode_context(raw)
      return unless raw

      attrs = {}
      offset = 0
      size = raw[:attrs].bytesize

      while offset + 2 <= size
        key_index = raw[:attrs].getbyte(offset)
        value_len = raw[:attrs].getbyte(offset + 1)
        break unless key_index && value_len
        break if offset + 2 + value_len > size

        attrs[key_index] = raw[:attrs].byteslice(offset + 2, value_len)
        offset += 2 + value_len
      end

      {
        trace_id: raw[:trace_id].unpack1("H*").to_s.to_i(16),
        span_id: raw[:span_id].unpack1("H*").to_s.to_i(16),
        local_root_span_id: attrs[0]&.to_i(16),
        valid: raw[:valid].getbyte(0) == 1,
        attrs: attrs,
      }
    end

    context "when enabled" do
      before(:all) do
        described_class.enable!
      end

      before do
        fail("libdatadog built without otel-thread-ctx") unless described_class.supported?
      end

      it "sets the thread context" do
        trace_id = 0xf0e1_d2c3_b4a5_9687_7869_5a4b_3c2d_1e0f
        span_id = 0xfedc_ba98_7654_3210
        local_root_span_id = 0xefcd_ab89_6745_2301

        described_class.set(trace_id: trace_id, span_id: span_id, local_root_span_id: local_root_span_id)

        expect(decode_context(described_class::Testing._native_read)).to include(
          trace_id: trace_id, span_id: span_id, local_root_span_id: local_root_span_id
        )
      end

      it "updates the thread context on fiber switch" do
        described_class.set(trace_id: 1, span_id: 2, local_root_span_id: 3)

        fiber = Fiber.new do
          described_class.set(trace_id: 11, span_id: 12, local_root_span_id: 13)

          Fiber.yield

          decode_context(described_class::Testing._native_read)
        end

        fiber.resume
        expect(decode_context(described_class::Testing._native_read)).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)

        fiber_context = fiber.resume
        expect(fiber_context).to include(trace_id: 11, span_id: 12, local_root_span_id: 13)

        expect(decode_context(described_class::Testing._native_read)).to include(trace_id: 1, span_id: 2, local_root_span_id: 3)
      end

      it "updates the thread context when switching between fibers" do
        fiber_a = Fiber.new do
          described_class.set(trace_id: 100, span_id: 101, local_root_span_id: 102)
          Fiber.yield
          decode_context(described_class::Testing._native_read)
        end

        fiber_b = Fiber.new do
          described_class.set(trace_id: 200, span_id: 201, local_root_span_id: 202)
          Fiber.yield
          decode_context(described_class::Testing._native_read)
        end

        fiber_a.resume
        fiber_b.resume

        expect(fiber_a.resume).to include(trace_id: 100, span_id: 101, local_root_span_id: 102)
        expect(fiber_b.resume).to include(trace_id: 200, span_id: 201, local_root_span_id: 202)

        expect(decode_context(described_class::Testing._native_read)).to be_nil
      end

      # In this example we create and kill a few threads,
      # and rely on the ruby_memcheck gem with spec:core_with_libdatadog_api_memcheck
      # to validate that we leave no memory behind for those threads.
      it "releases the thread context when a Thread exits" do
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

        expect(decode_context(described_class::Testing._native_read)).to be_nil
      end
    end
  end

  describe ".clear" do
    context "when enabled" do
      before(:all) do
        described_class.enable!
      end

      context "when a context record was attached" do
        before(:each) do
          described_class.set(trace_id: 1, span_id: 1, local_root_span_id: 1)
        end

        it "returns true" do
          expect(described_class.clear).to eq(true)
        end

        it "detaches the context record" do
          described_class.clear
          expect(described_class::Testing._native_read).to be_nil
        end

        it "remains detached after a fiber switch" do
          fiber = Fiber.new do
            described_class.set(trace_id: 1, span_id: 1, local_root_span_id: 1)
            described_class.clear

            Fiber.yield

            described_class::Testing._native_read
          end

          fiber.resume
          expect(fiber.resume).to be_nil
        end
      end

      context "when no record was attached" do
        it "returns false" do
          expect(described_class.clear).to eq(false)
        end
      end
    end
  end
end
