require "datadog/di/spec_helper"
require "datadog/di/transport/http"
require_relative "../snapshot_encoder_helpers"

RSpec.describe Datadog::DI::Transport::Input::Transport do
  di_test

  include SnapshotEncoderHelpers

  def snapshot_event(payload, event_type: Datadog::DI::GuardrailsTelemetry::EVENT_TYPE_SNAPSHOT)
    Datadog::DI::SnapshotEvent.new(payload: payload, event_type: event_type)
  end

  let(:telemetry) { nil }

  let(:guardrails_telemetry) do
    Datadog::DI::GuardrailsTelemetry.new(settings: settings, logger: logger, telemetry: telemetry)
  end

  let(:transport) do
    Datadog::DI::Transport::HTTP.input(agent_settings: agent_settings, logger: logger, telemetry: telemetry,
      guardrails_telemetry: guardrails_telemetry)
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new
  end

  let(:logger) do
    instance_double(Datadog::DI::Logger, debug: nil, trace: nil)
  end

  let(:tags) { [] }

  let(:noop_serialization_error_handler) { ->(_probe_id, _exc) {} }

  context "when snapshot contains escaped binary data" do
    context "with all 256 byte values" do
      # Create a string containing all possible byte values (0x00-0xFF)
      # This simulates capturing a binary buffer in dynamic instrumentation
      let(:binary_string) do
        (0..255).map { |i| i.chr(Encoding::BINARY) }.join.force_encoding(Encoding::BINARY)
      end

      # Simulate what the serializer produces after escaping binary data
      let(:escaped_binary) do
        result = +"b'"
        binary_string.each_byte do |byte|
          result << case byte
          when 0x09 then '\\t'
          when 0x0A then '\\n'
          when 0x0D then '\\r'
          when 0x27 then "\\'"
          when 0x5C then "\\\\"
          when 0x20..0x7E then byte.chr
          else format('\\x%02x', byte)
          end
        end
        result << "'"
        result.force_encoding(Encoding::UTF_8)
      end

      let(:snapshot) do
        {
          "id" => "test-snapshot",
          "timestamp" => Time.now.to_i,
          "captures" => {
            "locals" => {
              "binary_data" => {"type" => "String", "value" => escaped_binary},
            },
          },
        }
      end

      it "has all 256 unique bytes in original" do
        expect(binary_string.bytes.uniq.sort).to eq((0..255).to_a)
        expect(binary_string.encoding).to eq(Encoding::BINARY)
      end

      it "successfully serializes escaped binary through transport layer" do
        # Escaped binary format is JSON-safe
        expect(transport).to receive(:send_input_chunk).once
        expect {
          transport.send_input([snapshot_event(snapshot)], tags, on_serialization_error: noop_serialization_error_handler)
        }.not_to raise_error
      end

      it "produces valid JSON" do
        json_output = JSON.dump(snapshot)
        expect(json_output).to be_a(String)
        expect(json_output.encoding).to eq(Encoding::UTF_8)

        # Can round-trip through JSON
        parsed = JSON.parse(json_output)
        expect(parsed["captures"]["locals"]["binary_data"]).to eq(
          "type" => "String",
          "value" => escaped_binary,
        )
      end
    end

    context "with binary string that is invalid UTF-8" do
      # Create a string with bytes that are invalid UTF-8 sequences
      let(:binary_string) { "\x80\x81\x82\xFF\xFE".b }

      # After escaping binary data
      let(:escaped_binary) { "b'\\x80\\x81\\x82\\xff\\xfe'" }

      let(:snapshot) do
        {
          "id" => "test-snapshot",
          "captures" => {
            "locals" => {
              "binary_data" => {"type" => "String", "value" => escaped_binary},
            },
          },
        }
      end

      before do
        # Assert the original is indeed invalid UTF-8
        utf8_attempt = binary_string.dup.force_encoding(Encoding::UTF_8)
        expect(utf8_attempt.valid_encoding?).to be false
      end

      it "successfully serializes escaped binary string" do
        expect(transport).to receive(:send_input_chunk).once
        expect {
          transport.send_input([snapshot_event(snapshot)], tags, on_serialization_error: noop_serialization_error_handler)
        }.not_to raise_error
      end

      it "escaped binary is valid UTF-8" do
        expect(escaped_binary.encoding).to eq(Encoding::UTF_8)
        expect(escaped_binary.valid_encoding?).to be true
      end
    end
  end

  describe "size constants" do
    it "caps each snapshot at 1 MiB minus 4 KiB and each chunk at the cap" do
      expect(described_class::MAX_SERIALIZED_SNAPSHOT_SIZE).to eq 1_048_576
      expect(described_class::SIZE_CAP_HEADROOM).to eq 4_096
      expect(described_class::SNAPSHOT_SIZE_CAP).to eq 1_044_480
      expect(described_class::DEFAULT_CHUNK_SIZE).to eq described_class::SNAPSHOT_SIZE_CAP
      expect(described_class.const_defined?(:MAX_CHUNK_SIZE)).to be false
    end
  end

  context "when the combined size of snapshots serialized exceeds intake max" do
    before do
      # Reduce limits to make the test run faster and not require a lot of memory
      stub_const("Datadog::DI::Transport::Input::Transport::DEFAULT_CHUNK_SIZE", 100_000)
    end

    let(:snapshot) do
      # It doesn't matter what the payload is, generate a fake one here.
      # This payload serializes to 9781 bytes of JSON.
      1000.times.map do |i|
        [i, i]
      end.to_h
    end

    let(:snapshots) do
      # This serializes to 978201 bytes of JSON - just under 1 MB.
      [snapshot_event(snapshot)] * 100
    end

    it "chunks snapshots" do
      # Just under 1 MB payload, default chunk size ~100 KB, we expect 10 chunks
      expect(transport).to receive(:send_input_chunk).exactly(10).times do |chunked_payload, serialized_tags|
        expect(chunked_payload.length).to be < 100_000
        expect(chunked_payload.length).to be > 90_000
      end
      transport.send_input(snapshots, tags, on_serialization_error: noop_serialization_error_handler)
    end

    context "when individual snapshot exceeds intake max" do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }

      before do
        # Reduce the cap to force a reasonably-sized snapshot without
        # captured data to be dropped.
        stub_const("Datadog::DI::Transport::Input::Transport::SNAPSHOT_SIZE_CAP", 2_000)
      end

      let(:drop_message) { "di: dropping snapshot: pruning cannot fit it within the 2000-byte limit (payloadTooLarge)" }

      let(:small_snapshot) do
        20.times.map do |i|
          [i, i]
        end.to_h
      end

      let(:snapshots) do
        [snapshot_event(small_snapshot), snapshot_event(snapshot)]
      end

      it "drops snapshot that is too big" do
        expect(transport).to receive(:send_input_chunk).once do |chunked_payload, serialized_tags|
          expect(chunked_payload.length).to be < 1_000
          expect(chunked_payload.length).to be > 100
        end
        expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
          tags: {reason: "payloadTooLarge", event_type: "snapshot"})
        expect(telemetry).to receive(:inc).with("debugger", "guardrails.queue.dropped_bytes",
          JSON.dump(snapshot).bytesize, tags: {reason: "payloadTooLarge", event_type: "snapshot"})
        expect(telemetry).not_to receive(:inc).with("debugger", "capture.incomplete", any_args)
        expect_lazy_log(logger, :debug, drop_message)
        transport.send_input(snapshots, tags, on_serialization_error: noop_serialization_error_handler)
      end

      context "when the oversized event was produced by a log probe" do
        let(:snapshots) do
          [snapshot_event(snapshot, event_type: Datadog::DI::GuardrailsTelemetry::EVENT_TYPE_LOG)]
        end

        it "tags the drop metrics with the log event type" do
          expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
            tags: {reason: "payloadTooLarge", event_type: "log"})
          expect(telemetry).to receive(:inc).with("debugger", "guardrails.queue.dropped_bytes",
            JSON.dump(snapshot).bytesize, tags: {reason: "payloadTooLarge", event_type: "log"})
          expect(transport).not_to receive(:send_input_chunk)

          transport.send_input(snapshots, tags, on_serialization_error: noop_serialization_error_handler)
        end
      end

      context "when a snapshot is within the cap in characters but over it in bytes" do
        let(:snapshots) { [snapshot_event(multibyte_snapshot)] }

        let(:multibyte_snapshot) do
          {"capture" => ("\u20ac" * 1_000)}
        end

        before do
          encoded = JSON.dump(multibyte_snapshot)
          expect(encoded.length).to be < Datadog::DI::Transport::Input::Transport::SNAPSHOT_SIZE_CAP
          expect(encoded.bytesize).to be > Datadog::DI::Transport::Input::Transport::SNAPSHOT_SIZE_CAP
        end

        it "drops the snapshot measured in bytes" do
          expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
            tags: {reason: "payloadTooLarge", event_type: "snapshot"})
          expect(telemetry).to receive(:inc).with("debugger", "guardrails.queue.dropped_bytes",
            JSON.dump(multibyte_snapshot).bytesize, tags: {reason: "payloadTooLarge", event_type: "snapshot"})
          expect(transport).not_to receive(:send_input_chunk)

          transport.send_input(snapshots, tags, on_serialization_error: noop_serialization_error_handler)
        end
      end

      context "when emitting the payload-too-large drop metric raises" do
        let(:telemetry) { telemetry_double_raising_on_inc }

        let(:oversized_snapshot) do
          {
            debugger: {
              snapshot: {
                probe: {id: "large-probe"},
                data: (0...2_000).map { |i| i },
              },
            },
          }
        end

        let(:snapshots) { [snapshot_event(oversized_snapshot), snapshot_event(small_snapshot)] }

        it "keeps the drop contained and still sends the other snapshots" do
          serialization_errors = []
          on_serialization_error = ->(probe_id, _exc) { serialization_errors << probe_id }
          expect(telemetry).to receive(:report).twice
          expect_lazy_log_many(logger, :debug,
            drop_message,
            /error emitting debugger.events.dropped metric.*StandardError.*telemetry down/,
            /error emitting debugger.guardrails.queue.dropped_bytes metric.*StandardError.*telemetry down/)
          expect(transport).to receive(:send_input_chunk).once

          transport.send_input(snapshots, tags, on_serialization_error: on_serialization_error)

          expect(serialization_errors).to be_empty
        end

        context "and all exceptions propagate" do
          before do
            settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
          end

          it "raises the telemetry failure out of send_input without disabling the probe" do
            serialization_errors = []
            on_serialization_error = ->(probe_id, _exc) { serialization_errors << probe_id }
            expect(transport).not_to receive(:send_input_chunk)

            expect do
              transport.send_input(snapshots, tags, on_serialization_error: on_serialization_error)
            end.to raise_error(StandardError, "telemetry down")

            expect(serialization_errors).to be_empty
          end
        end

        context "and the emission raises a fatal exception" do
          let(:telemetry) { telemetry_double_raising_on_inc(exception: SystemExit) }

          it "re-raises the fatal exception out of send_input without disabling the probe" do
            serialization_errors = []
            on_serialization_error = ->(probe_id, _exc) { serialization_errors << probe_id }
            expect(transport).not_to receive(:send_input_chunk)

            expect do
              transport.send_input(snapshots, tags, on_serialization_error: on_serialization_error)
            end.to raise_error(SystemExit)

            expect(serialization_errors).to be_empty
          end
        end
      end

      context "when telemetry is nil" do
        let(:telemetry) { nil }

        it "drops the oversized snapshot and still sends the other snapshots" do
          expect(transport).to receive(:send_input_chunk).once
          expect_lazy_log(logger, :debug, drop_message)

          transport.send_input(snapshots, tags, on_serialization_error: noop_serialization_error_handler)
        end
      end
    end
  end

  context "when sending snapshot chunk fails" do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
    let(:snapshot) { {hello: "world"} }
    let(:snapshots) { [snapshot_event(snapshot)] }

    it "reports exception to telemetry and continues" do
      allow(logger).to receive(:debug)
      expect(transport).to receive(:send_input_chunk).and_raise(StandardError, "network error")

      expect(telemetry).to receive(:report) do |exc, description:|
        expect(exc).to be_a(StandardError)
        expect(exc.message).to eq("network error")
        expect(description).to eq("Error sending snapshot chunk")
      end

      # Should not raise despite the error
      expect do
        transport.send_input(snapshots, tags, on_serialization_error: noop_serialization_error_handler)
      end.not_to raise_error
    end
  end

  context "when snapshot JSON encoding fails" do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    # Create a payload with binary data that cannot be JSON-encoded
    let(:binary_string) { "\x80".force_encoding("ASCII-8BIT") }
    let(:bad_snapshot) do
      {
        debugger: {
          snapshot: {
            probe: {id: "bad-probe"},
            data: binary_string,
          },
        },
      }
    end

    let(:good_snapshot) do
      {
        debugger: {
          snapshot: {
            probe: {id: "good-probe"},
            data: "valid string",
          },
        },
      }
    end

    before do
      allow(logger).to receive(:debug)
      allow(telemetry).to receive(:report)
    end

    it "calls on_serialization_error callback with probe ID and exception" do
      errors = []
      on_error = ->(probe_id, exc) { errors << [probe_id, exc] }

      transport.send_input([snapshot_event(bad_snapshot)], tags, on_serialization_error: on_error)

      expect(errors.size).to eq(1)
      expect(errors.first[0]).to eq("bad-probe")
      # Any serialization error (JSON::GeneratorError, Encoding errors, etc.) is caught
      expect(errors.first[1]).to be_a(StandardError)
    end

    it "reports to telemetry" do
      expect(telemetry).to receive(:report) do |exc, description:|
        # Any serialization error is caught and reported
        expect(exc).to be_a(StandardError)
        expect(description).to eq("JSON encoding failed for snapshot")
      end

      transport.send_input([snapshot_event(bad_snapshot)], tags, on_serialization_error: noop_serialization_error_handler)
    end

    it "continues processing other snapshots after failure" do
      errors = []
      on_error = ->(probe_id, exc) { errors << probe_id }

      # Expect one chunk with only the good snapshot
      expect(transport).to receive(:send_input_chunk).once

      transport.send_input([snapshot_event(bad_snapshot), snapshot_event(good_snapshot)], tags, on_serialization_error: on_error)

      expect(errors).to eq(["bad-probe"])
    end

    it "isolates failures - only bad probe is reported" do
      errors = []
      on_error = ->(probe_id, exc) { errors << probe_id }

      transport.send_input([snapshot_event(good_snapshot), snapshot_event(bad_snapshot), snapshot_event(good_snapshot)],
        tags, on_serialization_error: on_error)

      # Only the bad probe should be reported
      expect(errors).to eq(["bad-probe"])
    end

    context "when on_serialization_error callback raises" do
      it "catches the callback exception and continues processing" do
        on_error = ->(_probe_id, _exc) { raise "callback error" }

        expect(transport).to receive(:send_input_chunk).once

        transport.send_input([snapshot_event(bad_snapshot), snapshot_event(good_snapshot)], tags, on_serialization_error: on_error)
      end

      it "reports the callback exception to telemetry" do
        on_error = ->(_probe_id, _exc) { raise "callback error" }

        reports = []
        allow(telemetry).to receive(:report) do |exc, description:|
          reports << {exc_class: exc.class, exc_message: exc.message, description: description}
        end

        transport.send_input([snapshot_event(bad_snapshot)], tags, on_serialization_error: on_error)

        expect(reports).to include(
          hash_including(exc_class: RuntimeError, exc_message: "callback error", description: "Error in serialization error callback"),
        )
      end
    end
  end

  describe "encoding failure logs" do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil) }
    let(:bad_snapshot) { {debugger: {snapshot: {probe: {id: "bad-probe"}, data: "\x80".b}}} }

    def debug_messages
      messages = []
      allow(logger).to receive(:debug) { |&block| messages << block.call }
      messages
    end

    it "ends the encoding failure log with the first backtrace frame" do
      messages = debug_messages
      errors = []

      transport.send_input([snapshot_event(bad_snapshot)], tags,
        on_serialization_error: ->(_probe_id, exc) { errors << exc })

      exc = errors.first
      expect(messages.first).to eq(
        "di: JSON encoding failed for snapshot (probe bad-probe): #{exc.class}: #{exc.message} (at #{exc.backtrace.first})",
      )
    end

    it "logs an encoding failure without a backtrace" do
      messages = debug_messages
      exc = StandardError.new("no frames")
      def exc.backtrace
        nil
      end
      allow(Datadog::DI::SnapshotEncoder).to receive(:encode).and_raise(exc)

      transport.send_input([snapshot_event(bad_snapshot)], tags,
        on_serialization_error: ->(_probe_id, _exc) { raise exc })

      expect(messages).to eq [
        "di: JSON encoding failed for snapshot (probe bad-probe): StandardError: no frames (at )",
        "di: error in serialization error callback for probe bad-probe: StandardError: no frames (at )",
      ]
    end

    it "ends the callback failure log with the callback's first backtrace frame" do
      messages = debug_messages
      callback_error = nil
      on_error = lambda do |_probe_id, _exc|
        raise "callback error"
      rescue => e
        callback_error = e
        raise
      end

      transport.send_input([snapshot_event(bad_snapshot)], tags, on_serialization_error: on_error)

      expect(messages.last).to eq(
        "di: error in serialization error callback for probe bad-probe: RuntimeError: callback error" \
        " (at #{callback_error.backtrace.first})",
      )
    end
  end

  context "with a snapshot larger than the size cap" do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }
    let(:oversized) { return_payload(array_value([string_value("a" * 300), string_value("b" * 300)])) }
    let(:within_cap) { return_payload(string_value("small")) }
    let(:cap) { JSON.dump(oversized).bytesize - 1 }
    let(:sent_chunks) { [] }

    before do
      stub_const("Datadog::DI::Transport::Input::Transport::SNAPSHOT_SIZE_CAP", cap)
      allow(transport).to receive(:send_input_chunk) { |chunked_payload, _| sent_chunks << chunked_payload }
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(42.5)
    end

    it "sends the pruned snapshot and reports it" do
      expect(telemetry).to receive(:inc).with("debugger", "capture.incomplete", 1,
        tags: {reason: "payloadTooLarge", event_type: "log"})
      expect(telemetry).not_to receive(:inc).with("debugger", "events.dropped", any_args)
      expect_lazy_log(logger, :trace,
        "di: pruned snapshot to fit size cap: #{cap + 1} -> #{cap - 312} bytes" \
        " (1 primitives replaced, 0 collections cut, 0 collections replaced)")

      expect do
        transport.send_input([snapshot_event(oversized, event_type: "log")], tags,
          on_serialization_error: noop_serialization_error_handler)
      end.to change(transport, :pruned_snapshot_count).from(0).to(1)
        .and change(transport, :last_pruned_at).from(nil).to(42.5)

      sent = JSON.parse(sent_chunks.fetch(0))
      expect(sent.length).to eq 1
      expect(sent.first.dig("debugger", "snapshot", "captures", "return", "arguments", "@return", "elements", 1))
        .to eq("pruned" => true)
    end

    it "reads the time before incrementing the count" do
      counts_at_read = []
      allow(Datadog::Core::Utils::Time).to receive(:get_time) do
        counts_at_read << transport.pruned_snapshot_count
        1.0
      end

      transport.send_input([snapshot_event(oversized), snapshot_event(oversized)], tags,
        on_serialization_error: noop_serialization_error_handler)

      expect(counts_at_read).to eq [0, 1]
      expect(transport.pruned_snapshot_count).to eq 2
    end

    it "leaves the pruning state unchanged for a snapshot within the cap" do
      expect(logger).not_to receive(:trace)
      expect(logger).not_to receive(:debug)
      expect(telemetry).not_to receive(:inc)

      expect do
        transport.send_input([snapshot_event(within_cap)], tags, on_serialization_error: noop_serialization_error_handler)
      end.not_to change { [transport.pruned_snapshot_count, transport.last_pruned_at] }

      expect(sent_chunks).to eq ["[#{JSON.dump(within_cap)}]"]
    end

    it "reports the pruned snapshots after the per-event loop and after the drops" do
      envelope_only = {padding: "p" * (cap + 1)}
      calls = []
      allow(guardrails_telemetry).to receive(:dropped) { |**kwargs| calls << [:dropped, kwargs] }
      allow(guardrails_telemetry).to receive(:capture_incomplete) { |**kwargs| calls << [:capture_incomplete, kwargs] }
      allow(Datadog::DI::SnapshotEncoder).to receive(:encode).and_wrap_original do |original, *args|
        calls << [:encode]
        original.call(*args)
      end

      transport.send_input([snapshot_event(oversized), snapshot_event(envelope_only)], tags,
        on_serialization_error: noop_serialization_error_handler)

      expect(calls).to eq [
        [:encode],
        [:encode],
        [:dropped, {reason: "payloadTooLarge", event_type: "snapshot", bytes: JSON.dump(envelope_only).bytesize}],
        [:capture_incomplete, {reason: "payloadTooLarge", event_type: "snapshot"}],
      ]
    end

    describe "#reset_pruning_state" do
      it "clears the count and the time" do
        transport.send_input([snapshot_event(oversized)], tags, on_serialization_error: noop_serialization_error_handler)

        expect { transport.reset_pruning_state }
          .to change { [transport.pruned_snapshot_count, transport.last_pruned_at] }.from([1, 42.5]).to([0, nil])
      end
    end
  end

  context "with snapshots made of 3-byte UTF-8 characters" do
    let(:snapshot) { {data: "\u20ac" * 100_000} }
    let(:sent_chunks) { [] }

    before do
      allow(transport).to receive(:send_input_chunk) { |chunked_payload, _| sent_chunks << chunked_payload }
    end

    it "chunks them by bytes so every request body fits the per-event limit" do
      transport.send_input([snapshot_event(snapshot)] * 6, tags, on_serialization_error: noop_serialization_error_handler)

      expect(JSON.dump(snapshot).length * 6).to be < described_class::DEFAULT_CHUNK_SIZE
      expect(sent_chunks.length).to eq 2
      sent_chunks.each do |chunk|
        expect(chunk.bytesize).to be <= described_class::MAX_SERIALIZED_SNAPSHOT_SIZE
      end
      expect(sent_chunks.sum { |chunk| JSON.parse(chunk).length }).to eq 6
    end
  end
end
