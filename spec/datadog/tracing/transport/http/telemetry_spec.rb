# frozen_string_literal: true

require "spec_helper"
require "datadog/tracing/transport/http"
require "datadog/tracing/component"
require "datadog/core/telemetry/component"

RSpec.describe Datadog::Tracing::Transport::HTTP::Telemetry do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:logger) { Logger.new(File::NULL) }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: logger) }
  let(:client) do
    Datadog::Core::Telemetry::Component.new(settings: settings, agent_settings: agent_settings, logger: logger, enabled: true)
  end
  let(:transport) do
    Datadog::Tracing::Transport::HTTP.default(agent_settings: agent_settings, logger: logger).tap do |transport|
      transport.telemetry = client
    end
  end
  let(:traces) { get_test_traces(2) }
  let(:v4) { "http://#{agent_settings.hostname}:#{agent_settings.port}/v0.4/traces" }
  let(:v3) { "http://#{agent_settings.hostname}:#{agent_settings.port}/v0.3/traces" }
  let(:metrics) do
    client.metrics_manager.flush!.flat_map { |event| event.payload[:series] }
  end

  before do
    allow(transport).to receive(:native_events_supported?).and_return(false)
  end

  after { client.shutdown! }

  def count(name, tags = [])
    series = metrics.find { |metric| metric[:metric] == name && metric[:tags].sort == tags.sort }
    series ? series[:points].sum { |point| point[1] } : 0
  end

  def ruby_tags(*tags)
    ["src_library:ruby", *tags]
  end

  it "reports successful payload sizes and post-encoding chunk and span counts" do
    bytes = []
    stub = stub_request(:post, v4).to_return do |request|
      bytes << request.body.bytesize
      {status: 200, body: '{"rate_by_service":{"service:test,env:":0.5}}'}
    end
    spans = traces.sum(&:length)
    2.times do
      responses = transport.send_traces(traces)
      expect(responses.first.ok?).to be true
      expect(responses.first.service_rates).to eq("service:test,env:" => 0.5)
    end
    expect(stub).to have_been_requested.twice
    expect(count("trace_api.requests", ruby_tags)).to eq(2)
    expect(count("trace_api.responses", ruby_tags("status_code:200"))).to eq(2)
    expect(count("trace_chunks_sent", ruby_tags)).to eq(4)
    expect(count("spans_enqueued_for_serialization")).to eq(spans * 2)
    expect(metrics.find { |metric| metric[:metric] == "trace_api.bytes" }).to eq(
      metric: "trace_api.bytes", points: bytes, tags: ruby_tags, common: true,
    )
    expect(metrics.all? { |metric| metric[:common] }).to be true
    expect(metrics.none? { |metric| metric[:tags].include?("src_library:libdatadog") }).to be true
  end

  it "counts fallback requests but reports only terminal outcomes" do
    first = stub_request(:post, v4).to_return(status: 404, body: "{}")
    last = stub_request(:post, v3).to_return(status: 200, body: "{}")
    expect(transport.send_traces(traces).first.ok?).to be true
    expect(first).to have_been_requested.once
    expect(last).to have_been_requested.once
    expect(count("trace_api.requests", ruby_tags)).to eq(2)
    expect(count("trace_api.responses", ruby_tags("status_code:200"))).to eq(1)
    expect(count("trace_api.responses", ruby_tags("status_code:404"))).to eq(0)
    expect(count("trace_chunks_dropped", ruby_tags("reason:send_failure"))).to eq(0)
    expect(count("spans_enqueued_for_serialization")).to eq(traces.sum(&:length) * 2)
    expect(metrics.find { |metric| metric[:metric] == "trace_api.bytes" }[:points].length).to eq(1)
  end

  it "reports terminal HTTP failures without successful byte samples" do
    stub_request(:post, v4).to_return(status: 503, body: "{}")
    expect(transport.send_traces(traces).first.server_error?).to be true
    expect(count("trace_api.requests", ruby_tags)).to eq(1)
    expect(count("trace_api.responses", ruby_tags("status_code:503"))).to eq(1)
    expect(count("trace_api.errors", ruby_tags("type:status_code"))).to eq(1)
    expect(count("trace_chunks_dropped", ruby_tags("reason:send_failure"))).to eq(2)
    expect(count("spans_dropped", ["reason:api_error"])).to eq(traces.sum(&:length))
    expect(metrics.none? { |metric| metric[:metric] == "trace_api.bytes" }).to be true
  end

  [
    Net::ReadTimeout,
    Errno::ETIMEDOUT,
    Errno::ECONNREFUSED,
    EOFError,
    SocketError,
    Net::HTTPBadResponse,
    OpenSSL::SSL::SSLError,
  ].each do |error|
    it "classifies #{error} from the exception" do
      stub_request(:post, v4).to_raise(error)
      expect(transport.send_traces(traces).first.internal_error?).to be true
      type = [Net::ReadTimeout, Errno::ETIMEDOUT].include?(error) ? "timeout" : "network"
      expect(count("trace_api.errors", ruby_tags("type:#{type}"))).to eq(1)
      expect(count("trace_chunks_dropped", ruby_tags("reason:send_failure"))).to eq(2)
      expect(count("spans_dropped", ["reason:api_error"])).to eq(traces.sum(&:length))
      expect(metrics.none? { |metric| metric[:metric] == "trace_api.responses" }).to be true
    end
  end

  it "does not confuse service-rate parsing failures with failed HTTP delivery" do
    stub_request(:post, v4).to_return(status: 200, body: "invalid JSON")
    expect(transport.send_traces(traces).first.internal_error?).to be true
    expect(count("trace_api.responses", ruby_tags("status_code:200"))).to eq(1)
    expect(count("trace_chunks_sent", ruby_tags)).to eq(2)
    expect(count("spans_dropped", ["reason:api_error"])).to eq(0)
  end

  it "distinguishes request-build failures from network failures" do
    stub_request(:post, v4).to_raise(ArgumentError.new("invalid header"))
    expect(transport.send_traces(traces).first.internal_error?).to be true
    expect(count("trace_api.requests", ruby_tags)).to eq(1)
    expect(count("trace_chunks_dropped", ruby_tags("reason:serialization_error"))).to eq(2)
    expect(count("spans_dropped", ["reason:serialization_error"])).to eq(traces.sum(&:length))
    expect(metrics.none? { |metric| metric[:metric] == "trace_api.errors" }).to be true
  end

  it "reports an aborted serialization batch and preserves the exception" do
    failure = ArgumentError.new("cannot encode")
    allow(Datadog::Tracing::Transport::Traces::Encoder).to receive(:encode_trace).and_raise(failure)
    expect { transport.send_traces(traces) }.to raise_error { |error| expect(error).to equal(failure) }
    expect(count("trace_chunks_dropped", ruby_tags("reason:serialization_error"))).to eq(2)
    expect(count("spans_dropped", ["reason:serialization_error"])).to eq(traces.sum(&:length))
    expect(count("trace_api.requests", ruby_tags)).to eq(0)
  end

  context "with split payloads" do
    before do
      stub_const("Datadog::Tracing::Transport::Traces::Chunker::DEFAULT_MAX_PAYLOAD_SIZE", 2)
      allow(Datadog::Tracing::Transport::Traces::Encoder).to receive(:encode_trace).and_return("aa")
    end

    it "keeps each payload sample and attributes spans to the failed payload" do
      traces.first.spans << traces.first.spans.first
      stub_request(:post, v4).to_return({status: 503, body: "{}"}, {status: 200, body: "{}"})
      responses = transport.send_traces(traces)
      expect(responses.map(&:ok?)).to eq([false, true])
      expect(count("trace_api.requests", ruby_tags)).to eq(2)
      expect(count("spans_dropped", ["reason:api_error"])).to eq(traces.first.length)
      expect(count("trace_chunks_sent", ruby_tags)).to eq(1)
      expect(metrics.find { |metric| metric[:metric] == "trace_api.bytes" }[:points]).to eq([3])
    end

    it "accounts for oversized traces without making a request" do
      allow(Datadog::Tracing::Transport::Traces::Encoder).to receive(:encode_trace).and_return("aaa")
      expect(transport.send_traces(traces)).to eq([])
      expect(count("trace_chunks_dropped", ruby_tags("reason:payload_too_large"))).to eq(2)
      expect(count("spans_dropped", ["reason:payload_too_large"])).to eq(traces.sum(&:length))
      expect(count("trace_api.requests", ruby_tags)).to eq(0)
    end

    it "does not count completed payloads as serialization drops" do
      traces = get_test_traces(4)
      calls = 0
      allow(Datadog::Tracing::Transport::Traces::Encoder).to receive(:encode_trace) do
        calls += 1
        raise "cannot encode" if calls == 3
        "aa"
      end
      stub_request(:post, v4).to_return(status: 200, body: "{}")
      expect { transport.send_traces(traces) }.to raise_error("cannot encode")
      expect(count("trace_api.requests", ruby_tags)).to eq(1)
      expect(count("trace_chunks_sent", ruby_tags)).to eq(1)
      expect(count("trace_chunks_dropped", ruby_tags("reason:serialization_error"))).to eq(3)
      expect(count("spans_dropped", ["reason:serialization_error"])).to eq(traces.drop(1).sum(&:length))
    end
  end

  it "does not record empty batches" do
    expect(transport.send_traces([])).to eq([])
    expect(metrics).to eq([])
  end

  context "when metrics are disabled" do
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap { |settings| settings.telemetry.metrics_enabled = false }
    end

    it "does not report observations" do
      stub_request(:post, v4).to_return(status: 200, body: "{}")
      expect(transport.send_traces(traces).first.ok?).to be true
      expect(metrics).to eq([])
    end
  end

  it "does not label unexpected exceptions as network errors" do
    stub_request(:post, v4).to_raise(RuntimeError.new("adapter failed"))
    expect(transport.send_traces(traces).first.internal_error?).to be true
    expect(count("trace_chunks_dropped", ruby_tags("reason:send_failure"))).to eq(2)
    expect(metrics.none? { |metric| metric[:metric] == "trace_api.errors" }).to be true
  end

  it "isolates failures to initialise observations" do
    allow(described_class::Batch).to receive(:new).and_raise("telemetry unavailable")
    stub_request(:post, v4).to_return(status: 200, body: "{}")
    expect(transport.send_traces(traces).first.ok?).to be true
    expect(metrics).to eq([])
  end

  it "isolates telemetry client failures from trace delivery" do
    allow(client).to receive(:inc).and_raise("telemetry unavailable")
    stub_request(:post, v4).to_return(status: 200, body: "{}")
    expect(transport.send_traces(traces).first.ok?).to be true
  end

  it "rebinds a retained Ruby transport through component construction" do
    replacement = Datadog::Core::Telemetry::Component.new(settings: settings, agent_settings: agent_settings, logger: logger, enabled: true)
    tracer = Datadog::Tracing::Tracer.new(writer: Datadog::Tracing::SyncWriter.new(transport: transport), logger: logger)
    begin
      Datadog::Tracing::Component.bind_transport_telemetry(tracer, replacement)
      client.shutdown!
      stub_request(:post, v4).to_return(status: 200, body: "{}")
      expect(transport.send_traces(traces).first.ok?).to be true
      expect(metrics).to eq([])
      expect(replacement.metrics_manager.flush!).not_to be_empty
    ensure
      tracer.shutdown!
      replacement.shutdown!
    end
  end
end
