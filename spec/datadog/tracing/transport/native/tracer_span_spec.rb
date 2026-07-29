# frozen_string_literal: true

require "datadog/core"
require "datadog/tracing/span"

RSpec.describe "Datadog::Tracing::Transport::Native::TracerSpan" do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:tracer_span_class) { native_module::TracerSpan }

  # ---------------------------------------------------------------------------
  # Helper: create a populated Ruby span
  # ---------------------------------------------------------------------------

  let(:now) { Time.now }
  let(:trace_id_128bit) { (1 << 64) | 0xdeadbeef }

  def make_ruby_span(overrides = {})
    defaults = {
      service: "test-service",
      resource: "GET /test",
      type: "web",
      id: 12345,
      parent_id: 67890,
      trace_id: trace_id_128bit,
      start_time: now,
      duration: 0.025,
      status: 0,
      meta: {"http.method" => "GET", "http.url" => "/test"},
      metrics: {"_dd.measured" => 1.0, "_sampling_priority_v1" => 2.0},
    }
    Datadog::Tracing::Span.new("web.request", **defaults.merge(overrides))
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "._native_from_span" do
    context "with a minimal span" do
      it "returns a TracerSpan" do
        span = Datadog::Tracing::Span.new("test.op")
        result = tracer_span_class._native_from_span(span)
        expect(result).to be_a(tracer_span_class)
      end
    end

    context "with all fields populated" do
      it "returns a TracerSpan" do
        result = tracer_span_class._native_from_span(make_ruby_span)
        expect(result).to be_a(tracer_span_class)
      end
    end

    context "with nil-able string fields set to nil" do
      it "does not raise" do
        span = make_ruby_span(service: nil, resource: nil, type: nil)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context "with empty meta and metrics hashes" do
      it "does not raise" do
        span = make_ruby_span(meta: {}, metrics: {})
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context "with an unstarted span (no start_time or duration)" do
      it "does not raise" do
        span = make_ruby_span(start_time: nil, duration: nil)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context "with a 128-bit trace ID" do
      it "does not raise" do
        big_id = (0xaabbccdd << 64) | 0x11223344
        span = make_ruby_span(trace_id: big_id)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context "with a 64-bit trace ID (high bits zero)" do
      it "does not raise" do
        span = make_ruby_span(trace_id: 42)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context "with non-string meta values (mixed hash)" do
      it "skips the non-string entries and warns with their count" do
        span = make_ruby_span(meta: {"good" => "value", "bad" => 123, nil => "also_bad"})

        # The two invalid entries (non-string value, non-string key) are
        # skipped; the skip is observable through the warning it logs.
        expect(Datadog.logger).to receive(:warn).with(/skipped 2 non-string meta entries/)

        expect(tracer_span_class._native_from_span(span)).to be_a(tracer_span_class)
      end
    end

    context "with a nil meta" do
      it "does not iterate or warn" do
        span = make_ruby_span(meta: nil)

        expect(Datadog.logger).to_not receive(:warn)

        expect(tracer_span_class._native_from_span(span)).to be_a(tracer_span_class)
      end
    end

    context "when the skip warning raises" do
      it "propagates the exception without crashing" do
        span = make_ruby_span(meta: {"good" => "value", "bad" => 123})
        allow(Datadog.logger).to receive(:warn).and_raise(RuntimeError, "logger boom")

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(RuntimeError, "logger boom")

        # A leaked rust span would surface as a crash under GC pressure.
        GC.start
      end
    end

    context "with non-numeric metrics values (mixed hash)" do
      it "skips the non-numeric entries and warns with their count" do
        span = make_ruby_span(metrics: {"_dd.measured" => 1.0, "bad" => "string"})

        expect(Datadog.logger).to receive(:warn).with(/skipped 1 non-numeric metrics entries/)

        expect(tracer_span_class._native_from_span(span)).to be_a(tracer_span_class)
      end
    end

    context "with meta_struct" do
      it "accepts string and symbol keys" do
        span = make_ruby_span
        span.set_metastruct_tag("_dd.stack", {frames: [{file: "app.rb", line: 42}]})
        span.set_metastruct_tag(:ai_guard, {messages: ["hello"]})

        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end

      it "does not call MessagePack for supported values" do
        value = {"supported" => [nil, true, 1, 1.5, "text", "\xff".b]}
        def value.to_msgpack
          raise "must not be called"
        end
        span = make_ruby_span
        span.set_metastruct_tag("native", value)

        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end

      it "rejects custom MessagePack encoders without calling them" do
        value = Object.new
        def value.to_msgpack
          raise "must not be called"
        end
        span = make_ruby_span
        span.set_metastruct_tag("custom", value)

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(TypeError, "unsupported meta_struct value type: Object")
      end

      it "rejects non-string top-level keys" do
        span = make_ruby_span
        span.set_metastruct_tag(1, "value")

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(TypeError, "meta_struct key must be a String or Symbol, got Integer")
      end

      it "rejects cyclic arrays and hashes" do
        array = []
        array << array
        hash = {}
        hash["self"] = hash

        [array, hash].each do |value|
          span = make_ruby_span
          span.set_metastruct_tag("cyclic", value)
          expect { tracer_span_class._native_from_span(span) }
            .to raise_error(ArgumentError, "meta_struct value contains a cycle")
        end
      end

      it "rejects values deeper than 64 containers" do
        value = nil
        65.times { value = [value] }
        span = make_ruby_span
        span.set_metastruct_tag("deep", value)

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(ArgumentError, "meta_struct value exceeds maximum depth of 64")
      end

      it "rejects integers outside the native range" do
        span = make_ruby_span
        span.set_metastruct_tag("large", 1 << 64)

        expect { tracer_span_class._native_from_span(span) }.to raise_error(RangeError)
      end

      it "rejects invalid UTF-8 strings" do
        span = make_ruby_span
        span.set_metastruct_tag("invalid", (+"\xff").force_encoding(Encoding::UTF_8))

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(EncodingError, "meta_struct string is not valid UTF-8")

        GC.start
      end
    end

    context "when called multiple times on the same span" do
      it "returns a distinct instance each time" do
        span = make_ruby_span
        r1 = tracer_span_class._native_from_span(span)
        r2 = tracer_span_class._native_from_span(span)
        expect(r1).not_to equal(r2)
      end
    end

    context "GC safety" do
      it "does not crash when instances are garbage collected" do
        20.times { tracer_span_class._native_from_span(make_ruby_span) }
        GC.start
        GC.start
      end
    end

    it "cannot be allocated directly" do
      expect { tracer_span_class.new }.to raise_error(TypeError)
    end
  end
end
