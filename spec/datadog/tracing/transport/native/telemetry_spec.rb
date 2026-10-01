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
      tags: ["src_library:libdatadog", "status_code:200"],)
    expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 123, tags: ["src_library:libdatadog"])

    reporter.record(requests_count: 3, chunks_sent: 2, spans_enqueued_for_serialization: 5,
      responses_count: 1, status_code: 200, bytes_sent: 123,)
  end

  it "preserves separate byte samples across sends" do
    expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 123, tags: ["src_library:libdatadog"]).ordered
    expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 456, tags: ["src_library:libdatadog"]).ordered
    reporter.record(bytes_sent: 123)
    reporter.record(bytes_sent: 456)
  end

  it "does not add a source tag to span drops or collapse observations" do
    expect(client).to receive(:inc).with("tracers", "spans_dropped", 5, tags: ["reason:api_error"])
    expect(client).to receive(:inc).with("tracers", "stats_collapsed_spans", 2, tags: ["collapsed:whole_key"])
    expect(client).to receive(:inc).with("tracers", "stats_collapsed_spans", 3,
      tags: ["collapsed:resource", "collapsed:http_endpoint"],)
    reporter.record(spans_dropped_api_error: 5)
    reporter.record_stats([2, 0, 0, 3])
  end

  it "preserves each native failure classification" do
    %w[network timeout status_code].each do |type|
      expect(client).to receive(:inc).with("tracers", "trace_api.errors", 1,
        tags: ["src_library:libdatadog", "type:#{type}"],)
      reporter.record("errors_#{type}": 1)
    end
    {
      serialization_error: "serialization_error",
      send_failure: "send_failure",
      p0: "p0_drop",
      by_trace_filter: "trace_filters",
    }.each do |field, reason|
      expect(client).to receive(:inc).with("tracers", "trace_chunks_dropped", 2,
        tags: ["src_library:libdatadog", "reason:#{reason}"],)
      reporter.record("chunks_dropped_#{field}": 2)
    end
  end

  it "suppresses zero values and disabled telemetry" do
    expect(client).not_to receive(:inc)
    expect(client).not_to receive(:distribution)
    reporter.record(bytes_sent: 0, requests_count: 0)
    allow(client).to receive(:enabled?).and_return(false)
    reporter.record(bytes_sent: 123, requests_count: 1)
    reporter.record_stats([1])
  end

  it "isolates telemetry failures" do
    allow(client).to receive(:inc).and_raise("telemetry unavailable")
    expect { reporter.record(requests_count: 1) }.not_to raise_error
    expect { reporter.record_stats([1]) }.not_to raise_error
  end

  context "with a native exporter" do
    let(:exporter) { double("exporter") }
    subject(:reporter) { described_class.new(client, exporter) }

    it "rebinds collection to a replacement component" do
      replacement = instance_double(Datadog::Core::Telemetry::Component, enabled?: true)
      allow(client).to receive(:register_metrics_collector)
      reporter
      expect(client).to have_received(:register_metrics_collector).with(reporter)
      expect(client).to receive(:unregister_metrics_collector).with(reporter)
      expect(replacement).to receive(:register_metrics_collector).with(reporter)
      reporter.client = replacement
      expect(exporter).to receive(:_native_take_stats_observations).and_return([2])
      expect(replacement).to receive(:inc).with("tracers", "stats_collapsed_spans", 2, tags: ["collapsed:whole_key"])
      reporter.collect
      expect(replacement).to receive(:unregister_metrics_collector).with(reporter)
      reporter.close
      reporter.collect
    end
  end
end
