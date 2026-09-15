# frozen_string_literal: true

require "spec_helper"
require "datadog/lambda"

RSpec.describe Datadog::Lambda do
  describe ".metric" do
    it "writes the Forwarder JSON format when the extension is absent" do
      allow(Datadog::Tracing::Contrib::AwsLambdaRic::Lifecycle).to receive(:extension_running?).and_return(false)
      time = Time.utc(2023, 1, 7, 12, 30)

      expect { described_class.metric("metric.name", 42, time: time, env: "dev") }
        .to output(/"e":1673094600.*"m":"metric.name".*"env:dev".*"v":42/).to_stdout
    end

    it "validates metric inputs" do
      expect { described_class.metric(:name, 42) }.to raise_error("name must be a string")
      expect { described_class.metric("name", "42") }.to raise_error("value must be a number")
    end
  end

  describe ".trace_context" do
    it "returns an empty hash outside a trace" do
      expect(described_class.trace_context).to eq({})
    end

    it "returns the active trace identifiers" do
      Datadog::Tracing.trace("test") do |span|
        expect(described_class.trace_context).to include(
          trace_id: span.trace_id.to_s,
          parent_id: span.id.to_s,
          source: "ddtrace",
        )
      end
    end
  end
end
