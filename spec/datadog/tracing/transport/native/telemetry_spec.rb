# frozen_string_literal: true

require "datadog/tracing/transport/native/telemetry"
require "datadog/core/telemetry/component"

RSpec.describe Datadog::Tracing::Transport::Native::Telemetry do
  subject(:reporter) { described_class.new(client) }

  let(:client) { instance_double(Datadog::Core::Telemetry::Component, enabled?: true) }

  it "forwards successful observations with the native metric contract" do
    expect(client).to receive(:inc).with("tracers", "trace_api.requests", 3, tags: ["src_library:libdatadog"])
    expect(client).to receive(:inc).with("tracers", "trace_chunks_sent", 2, tags: ["src_library:libdatadog"])
    expect(client).to receive(:inc).with("tracers", "spans_enqueued_for_serialization", 5, tags: [])
    expect(client).to receive(:inc).with("tracers", "trace_api.responses", 1,
      tags: ["src_library:libdatadog", "status_code:200"])
    expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 123, tags: ["src_library:libdatadog"])

    reporter.record(requests_count: 3, chunks_sent: 2, spans_enqueued_for_serialization: 5,
      responses_count: 1, status_code: 200, bytes_sent: 123)
  end

  it "preserves separate byte samples across sends" do
    expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 123, tags: ["src_library:libdatadog"]).ordered
    expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 456, tags: ["src_library:libdatadog"]).ordered
    reporter.record(bytes_sent: 123)
    reporter.record(bytes_sent: 456)
  end

  it "does not add a source tag to span drops" do
    expect(client).to receive(:inc).with("tracers", "spans_dropped", 5, tags: ["reason:api_error"])
    reporter.record(spans_dropped_api_error: 5)
  end

  it "preserves each native failure classification" do
    %w[network timeout status_code].each do |type|
      expect(client).to receive(:inc).with("tracers", "trace_api.errors", 1,
        tags: ["src_library:libdatadog", "type:#{type}"])
      reporter.record("errors_#{type}": 1)
    end
    {
      serialization_error: "serialization_error",
      send_failure: "send_failure",
    }.each do |field, reason|
      expect(client).to receive(:inc).with("tracers", "trace_chunks_dropped", 2,
        tags: ["src_library:libdatadog", "reason:#{reason}"])
      reporter.record("chunks_dropped_#{field}": 2)
    end
  end

  it "reports chunks cancelled before dispatch without trace API metrics" do
    expect(client).to receive(:inc).with("tracers", "trace_chunks_dropped", 2,
      tags: ["src_library:libdatadog", "reason:cancelled"],)
    expect(client).to receive(:inc).with("tracers", "spans_enqueued_for_serialization", 3, tags: [])
    expect(client).to receive(:inc).with("tracers", "spans_dropped", 3, tags: ["reason:cancelled"])
    expect(client).not_to receive(:distribution)

    reporter.record(chunks_dropped_cancelled: 2, spans_dropped_cancelled: 3, spans_enqueued_for_serialization: 3)
  end

  it "suppresses zero values and disabled telemetry" do
    expect(client).not_to receive(:inc)
    expect(client).not_to receive(:distribution)
    reporter.record(bytes_sent: 0, requests_count: 0)
    allow(client).to receive(:enabled?).and_return(false)
    reporter.record(bytes_sent: 123, requests_count: 1)
  end

  it "isolates telemetry failures" do
    allow(client).to receive(:inc).and_raise("telemetry unavailable")
    expect { reporter.record(requests_count: 1) }.not_to raise_error
  end

  it "forwards observations to a replacement component" do
    replacement = instance_double(Datadog::Core::Telemetry::Component, enabled?: true)
    expect(client).not_to receive(:inc)
    expect(replacement).to receive(:inc).with("tracers", "trace_chunks_sent", 2, tags: ["src_library:libdatadog"])

    reporter.client = replacement
    reporter.record(chunks_sent: 2)
  end
end
