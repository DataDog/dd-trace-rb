# frozen_string_literal: true

require "spec_helper"
require "datadog/opentelemetry/sdk"

RSpec.describe Datadog::OpenTelemetry::SDK do
  describe ".telemetry_inc" do
    subject(:telemetry_inc) { described_class.telemetry_inc(metric_name, value) }

    let(:metric_name) { "otel.export_attempts" }
    let(:value) { 1 }
    let(:components) { double(telemetry: telemetry) }

    before do
      allow(Datadog).to receive(:send).with(:components).and_return(components)
    end

    context "when telemetry is available" do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

      it "increments the telemetry metric under the tracers namespace" do
        expect(telemetry).to receive(:inc).with(
          "tracers",
          "otel.export_attempts",
          1,
          tags: {"protocol" => "http", "encoding" => "protobuf"}
        )

        telemetry_inc
      end
    end

    context "when telemetry is unavailable" do
      let(:telemetry) { nil }

      it { is_expected.to be nil }
    end
  end
end
