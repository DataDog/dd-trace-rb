# frozen_string_literal: true

require "spec_helper"
require "datadog/tracing/transport/telemetry"
require "datadog/core/telemetry/component"

RSpec.describe Datadog::Tracing::Transport::Telemetry do
  ["ruby", "libdatadog"].each do |source|
    context "with #{source} observations" do
      subject(:reporter) { described_class.new(client, source: source) }

      let(:client) { instance_double(Datadog::Core::Telemetry::Component, enabled?: true) }

      it "tags exporter measurements without adding source tags to span metrics" do
        expect(client).to receive(:inc).with("tracers", "trace_api.requests", 2, tags: ["src_library:#{source}"])
        expect(client).to receive(:inc).with("tracers", "spans_dropped", 3, tags: ["reason:api_error"])
        expect(client).to receive(:distribution).with("tracers", "trace_api.bytes", 42, tags: ["src_library:#{source}"])
        reporter.record(requests_count: 2, spans_dropped_api_error: 3, bytes_sent: 42)
      end
    end
  end
end
