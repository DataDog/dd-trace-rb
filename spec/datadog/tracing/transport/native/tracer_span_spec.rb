# frozen_string_literal: true

require "datadog/core"
require "datadog/tracing/span"
require "datadog/tracing/span_event"

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

      it "frees the span when Warning.warn raises for a huge Bignum" do
        span = make_ruby_span(metrics: {"huge" => (1 << 65_536)})
        verbose = $VERBOSE
        $VERBOSE = true
        allow(Warning).to receive(:warn).and_raise(RuntimeError, "warning boom")

        20.times do
          expect { tracer_span_class._native_from_span(span) }
            .to raise_error(RuntimeError, "warning boom")
        end

        GC.start
      ensure
        $VERBOSE = verbose
      end

      it "frees the span when Warning.warn mutates the iterated hash" do
        metrics = {"huge" => (1 << 65_536)}
        span = make_ruby_span(metrics: metrics)
        verbose = $VERBOSE
        $VERBOSE = true
        allow(Warning).to receive(:warn) { metrics["added by warning"] = 1.0 }

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(RuntimeError, /can't add a new key into hash during iteration/)

        GC.start
      ensure
        $VERBOSE = verbose
      end

      it "remains safe when warning code mutates the converted hash" do
        meta = {"invalid" => Object.new}
        span = make_ruby_span(meta: meta)
        allow(Datadog.logger).to receive(:warn) do
          meta["added by logger"] = Object.new
          raise "logger mutated meta"
        end

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(RuntimeError, "logger mutated meta")
        expect(meta).to have_key("added by logger")

        GC.start
      end
    end

    context "when Ruby conversion raises after native events are allocated" do
      it "cleans up detached events and propagates the exception" do
        event = Datadog::Tracing::SpanEvent.new("event", time_unix_nano: 123)
        span = make_ruby_span(duration: nil, events: [event])
        allow(span).to receive(:duration).and_raise(RuntimeError, "duration boom")

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(RuntimeError, "duration boom")

        GC.start
        expect(tracer_span_class._native_from_span(make_ruby_span(events: [event])))
          .to be_a(tracer_span_class)
      end
    end

    context "when libdatadog rejects event input" do
      it "cleans up the event allocation and raises" do
        invalid = "\xFF".b.force_encoding(Encoding::UTF_8)
        event = Datadog::Tracing::SpanEvent.new("event", attributes: {"invalid" => invalid})

        expect { tracer_span_class._native_from_span(make_ruby_span(events: [event])) }
          .to raise_error(RuntimeError, /Failed to set span event attribute/)

        GC.start
        valid = Datadog::Tracing::SpanEvent.new("event", attributes: {"valid" => "value"})
        expect(tracer_span_class._native_from_span(make_ruby_span(events: [valid])))
          .to be_a(tracer_span_class)
      end
    end

    context "with malformed native event input" do
      it "rejects it before allocating Rust resources" do
        event = double(
          "malformed event",
          to_native_format: {
            "name" => "event",
            "time_unix_nano" => 123,
            "attributes" => {"invalid" => {type: 99}},
          }
        )

        expect { tracer_span_class._native_from_span(make_ruby_span(events: [event])) }
          .to raise_error(ArgumentError, /unsupported span event attribute type/)
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

      it "skips keys outside the agent string-key contract" do
        span = make_ruby_span
        span.set_metastruct_tag(123, {ignored: true})

        expect(Datadog.logger).to receive(:warn)
          .with(/skipped 1 meta_struct entries with non-string keys/)

        expect(tracer_span_class._native_from_span(span)).to be_a(tracer_span_class)
      end

      it "supports zero-argument custom MessagePack encoders" do
        value = Object.new
        def value.to_msgpack
          {"custom" => true}.to_msgpack
        end
        span = make_ruby_span
        span.set_metastruct_tag("custom", value)

        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end

      it "propagates MessagePack encoding errors without crashing" do
        value = Object.new
        def value.to_msgpack
          raise "encoding failed"
        end
        span = make_ruby_span
        span.set_metastruct_tag("broken", value)

        expect { tracer_span_class._native_from_span(span) }
          .to raise_error(RuntimeError, "encoding failed")

        GC.start
      end
    end

    context "when libdatadog rejects meta or metrics" do
      it "frees the span before raising" do
        invalid = "\xFF".b.force_encoding(Encoding::UTF_8)
        spans = [
          make_ruby_span(meta: {invalid => "value"}),
          make_ruby_span(metrics: {invalid => 1.0}),
        ]

        20.times do
          spans.each do |span|
            expect { tracer_span_class._native_from_span(span) }
              .to raise_error(RuntimeError, /Failed to set span (meta|metric)/)
          end
        end

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
