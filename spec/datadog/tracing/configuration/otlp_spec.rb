require "spec_helper"

require "datadog/core/configuration/settings"
require "datadog/tracing/configuration/otlp"

RSpec.describe Datadog::Tracing::Configuration::OTLP do
  let(:otlp_environment) do
    [
      "DD_TRACE_AGENT_PROTOCOL_VERSION",
      "OTEL_TRACES_EXPORTER",
      "OTEL_EXPORTER_OTLP_ENDPOINT",
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
      "OTEL_EXPORTER_OTLP_HEADERS",
      "OTEL_EXPORTER_OTLP_TRACES_HEADERS",
      "OTEL_EXPORTER_OTLP_TIMEOUT",
      "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT",
      "OTEL_EXPORTER_OTLP_PROTOCOL",
      "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL",
    ].each_with_object({}) { |name, env| env[name] = nil }
  end

  let(:agent_settings) { double("agent_settings", hostname: "agent.internal") }

  def with_otlp_settings(env = {})
    ClimateControl.modify(otlp_environment.merge(env)) do
      settings = Datadog::Core::Configuration::Settings.new
      yield settings
    end
  end

  def resolve(env = {})
    with_otlp_settings(env) do |settings|
      return described_class.transport_options(
        settings.tracing.otlp,
        settings.opentelemetry.exporter,
        agent_settings
      )
    end
  end

  describe ".enabled?" do
    it "enables OTLP case-insensitively" do
      with_otlp_settings("OTEL_TRACES_EXPORTER" => "OtLp") do |settings|
        expect(described_class.enabled?(settings.tracing.otlp)).to be true
      end
    end

    it "does not enable OTLP for another exporter" do
      with_otlp_settings("OTEL_TRACES_EXPORTER" => "none") do |settings|
        expect(described_class.enabled?(settings.tracing.otlp)).to be false
      end
    end

    it "lets DD_TRACE_AGENT_PROTOCOL_VERSION disable OTLP" do
      with_otlp_settings(
        "OTEL_TRACES_EXPORTER" => "otlp",
        "DD_TRACE_AGENT_PROTOCOL_VERSION" => "v0.5"
      ) do |settings|
        expect(described_class.enabled?(settings.tracing.otlp)).to be false
      end
    end
  end

  describe ".transport_options" do
    it "uses the agent host for the default endpoint" do
      expect(resolve("OTEL_TRACES_EXPORTER" => "otlp")[:otlp_endpoint])
        .to eq("http://agent.internal:4318/v1/traces")
    end

    it "uses localhost when the Agent is configured through a Unix socket" do
      allow(agent_settings).to receive(:hostname).and_return(nil)

      expect(resolve[:otlp_endpoint]).to eq("http://127.0.0.1:4318/v1/traces")
    end

    it "appends the traces path to the general endpoint" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_ENDPOINT" => "http://collector:4318/"
      )[:otlp_endpoint]).to eq("http://collector:4318/v1/traces")
    end

    it "preserves a general endpoint path before appending the traces path" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_ENDPOINT" => "http://collector:4318/base"
      )[:otlp_endpoint]).to eq("http://collector:4318/base/v1/traces")
    end

    it "uses the trace-specific endpoint exactly" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_ENDPOINT" => "http://global:4318",
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "http://traces:9000/custom"
      )[:otlp_endpoint]).to eq("http://traces:9000/custom")
    end

    it "treats empty endpoints as unset" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_ENDPOINT" => "",
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => ""
      )[:otlp_endpoint]).to eq("http://agent.internal:4318/v1/traces")
    end

    it "uses trace-specific headers and ignores malformed entries" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_HEADERS" => "global=one",
        "OTEL_EXPORTER_OTLP_TRACES_HEADERS" => "first=one, malformed, second = two=2"
      )[:otlp_headers]).to eq("first" => "one", "second" => "two=2")
    end

    it "uses general headers when trace-specific headers are unset" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_HEADERS" => "authorization=Bearer%20token,route=ruby"
      )[:otlp_headers]).to eq(
        "authorization" => "Bearer%20token",
        "route" => "ruby"
      )
    end

    it "ignores malformed general header entries without dropping valid headers" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_HEADERS" => "first=one, malformed, second=two"
      )[:otlp_headers]).to eq("first" => "one", "second" => "two")
    end

    it "uses trace-specific timeout and protocol" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_TIMEOUT" => "9000",
        "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT" => "2500",
        "OTEL_EXPORTER_OTLP_PROTOCOL" => "http/json",
        "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL" => "http/protobuf"
      )).to include(otlp_timeout_millis: 2500, otlp_protocol: "http/protobuf")
    end

    it "normalizes protocol whitespace and case" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL" => " HTTP/JSON "
      )[:otlp_protocol]).to eq("http/json")
    end

    it "preserves a future grpc selection from the general protocol setting" do
      expect(resolve(
        "OTEL_EXPORTER_OTLP_PROTOCOL" => " GRPC "
      )[:otlp_protocol]).to eq("grpc")
    end

    it "defaults to a ten-second timeout and grpc protocol selection" do
      expect(resolve).to include(otlp_timeout_millis: 10_000, otlp_protocol: "grpc")
    end
  end
end
