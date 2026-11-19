# frozen_string_literal: true

require "datadog/tracing/span"
require "datadog/tracing/trace_segment"

RSpec.shared_examples "transport provenance on the wire" do |identity|
  let(:root) { Datadog::Tracing::Span.new("root", id: 100, parent_id: parent_id, trace_id: 123, service: "app") }
  let(:child) { Datadog::Tracing::Span.new("child", id: 101, parent_id: 100, trace_id: 123, service: "app") }
  let(:entry) do
    Datadog::Tracing::Span.new("entry", id: 102, parent_id: 100, trace_id: 123, service: "db").tap do |span|
      span.set_metric("_dd.top_level", 1)
    end
  end
  let(:parent_id) { 0 }
  let(:root_span_id) { root.id }
  let(:spans) { [child, root, entry] }
  let(:trace) do
    Datadog::Tracing::TraceSegment.new(spans, id: 123, root_span_id: root_span_id, sampling_priority: 2)
  end

  before do
    Datadog.configuration.telemetry.enabled = false
    Datadog.configuration.telemetry.metrics_enabled = false
  end

  shared_examples "a labelled local root" do
    it "labels only the known local root, preserving sampling metadata" do
      decoded = send_and_decode([trace]).first

      expect(decoded.map { |span| [span["span_id"], span.fetch("meta", {})["_dd.tracing.transport"]] })
        .to contain_exactly([100, identity], [101, nil], [102, nil])
      decoded_root = decoded.find { |span| span["span_id"] == 100 }
      expect(decoded_root.fetch("parent_id", 0)).to eq(parent_id)
      expect(decoded_root.fetch("metrics")["_sampling_priority_v1"]).to eq(2)
    end
  end

  include_examples "a labelled local root"

  context "with a remote parent" do
    let(:parent_id) { 42 }

    include_examples "a labelled local root"
  end

  context "with telemetry enabled but metrics disabled" do
    before { Datadog.configuration.telemetry.enabled = true }

    include_examples "a labelled local root"
  end

  context "with a rootless partial chunk containing a service entry" do
    let(:spans) { [child, entry] }
    let(:root_span_id) { nil }

    it "does not label the chunk representative or service entry" do
      decoded = send_and_decode([trace]).first

      expect(decoded.size).to eq(2)
      expect(decoded.map { |span| span.fetch("meta", {}) }).not_to include(have_key("_dd.tracing.transport"))
    end

    context "when the root ID is known but its span was removed" do
      let(:root_span_id) { root.id }

      it "does not label a replacement root" do
        decoded = send_and_decode([trace]).first

        expect(decoded.map { |span| span.fetch("meta", {}) }).not_to include(have_key("_dd.tracing.transport"))
      end
    end

    context "without a service entry" do
      let(:spans) { [child] }

      it "leaves the child unlabelled" do
        decoded = send_and_decode([trace]).first

        expect(decoded.size).to eq(1)
        expect(decoded.first.fetch("meta", {})).not_to have_key("_dd.tracing.transport")
      end
    end
  end

  it "labels the roots of each trace in a batch" do
    other_root = Datadog::Tracing::Span.new("other", id: 200, trace_id: 456, service: "app")
    other = Datadog::Tracing::TraceSegment.new([other_root], id: 456, root_span_id: 200)

    decoded = send_and_decode([trace, other])

    expect(decoded.size).to eq(2)
    labelled = decoded.flatten.select { |span| span.fetch("meta", {}).key?("_dd.tracing.transport") }
    expect(labelled.map { |span| [span["span_id"], span["meta"]["_dd.tracing.transport"]] })
      .to contain_exactly([100, identity], [200, identity])
  end
end
