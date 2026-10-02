require "spec_helper"

require "datadog/tracing/transport/http"
require "datadog/tracing/component"
require "datadog/tracing/transport/native"
require_relative "provenance_shared_examples"

RSpec.describe Datadog::Tracing::Transport::HTTP do
  let(:logger) { logger_allowing_debug }

  describe "transport provenance", webmock: true do
    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettings.new(
        adapter: :net_http,
        hostname: "127.0.0.1",
        port: 8126,
      )
    end
    let(:transport) { described_class.default(agent_settings: agent_settings, logger: logger) }
    let(:payloads) { [] }

    before do
      Datadog.configuration.tracing.native_span_events = false
      stub_request(:post, "http://127.0.0.1:8126/v0.4/traces").to_return do |request|
        payloads << MessagePack.unpack(request.body)
        {status: 200, body: '{"rate_by_service":{}}'}
      end
    end

    def send_and_decode(traces)
      expect(transport.send_traces(traces)).to all(be_ok)
      payloads.flatten(1)
    end

    it_behaves_like "transport provenance on the wire", "ruby"

    context "when payload chunking is required" do
      before { stub_const("Datadog::Tracing::Transport::Traces::Chunker::DEFAULT_MAX_PAYLOAD_SIZE", 1000) }

      it "preserves the identity in every payload" do
        traces = Array.new(3) do |i|
          span = Datadog::Tracing::Span.new("root", id: i + 1, trace_id: i + 1, service: "app")
          span.set_tag("padding", "x" * 500)
          Datadog::Tracing::TraceSegment.new([span], id: i + 1, root_span_id: span.id)
        end

        decoded = send_and_decode(traces)

        expect(payloads.size).to eq(3)
        expect(decoded.flatten.map { |span| span.fetch("meta")["_dd.tracing.transport"] }).to eq(["ruby"] * 3)
      end
    end

    [404, 415].each do |status|
      context "when v0.4 returns #{status}" do
        before do
          stub_request(:post, "http://127.0.0.1:8126/v0.4/traces").to_return do |request|
            payloads << MessagePack.unpack(request.body)
            {status: status}
          end
          stub_request(:post, "http://127.0.0.1:8126/v0.3/traces").to_return do |request|
            payloads << MessagePack.unpack(request.body)
            {status: 200, body: "{}"}
          end
        end

        it "keeps the Ruby identity across protocol downgrade" do
          span = Datadog::Tracing::Span.new("root", id: 1, trace_id: 2, service: "app")
          trace = Datadog::Tracing::TraceSegment.new([span], id: 2, root_span_id: 1)

          decoded = send_and_decode([trace])

          expect(transport.current_api_id).to eq("v0.3")
          expect(payloads.size).to eq(2)
          expect(decoded.flatten.map { |s| s.fetch("meta")["_dd.tracing.transport"] }).to eq(["ruby", "ruby"])
        end
      end
    end

    context "when native transport is requested but unavailable" do
      let(:settings) do
        Datadog::Core::Configuration::Settings.new.tap { |s| s.tracing.native_transport = true }
      end
      let(:writer) { Datadog::Tracing::Component.send(:build_writer, settings, agent_settings) }

      before do
        allow(Datadog::Tracing::Transport::Native).to receive(:supported?).and_return(false)
      end

      after { writer.stop }

      it "emits the identity of the Ruby fallback" do
        span = Datadog::Tracing::Span.new("root", id: 1, trace_id: 2, service: "app")
        trace = Datadog::Tracing::TraceSegment.new([span], id: 2, root_span_id: 1)

        writer.write(trace)
        writer.stop

        expect(payloads.flatten(2).map { |s| s.fetch("meta")["_dd.tracing.transport"] }).to eq(["ruby"])
      end

      context "with a custom transport" do
        let(:custom) { instance_double(Datadog::Tracing::Transport::Traces::Transport) }
        before { settings.tracing.writer_options = {transport: custom} }

        it "leaves identity assignment to that transport" do
          span = Datadog::Tracing::Span.new("root", id: 1, trace_id: 2, service: "app")
          trace = Datadog::Tracing::TraceSegment.new([span], id: 2, root_span_id: 1)
          captured = []
          allow(custom).to receive(:send_traces) do |traces|
            captured.concat(traces.flat_map(&:spans).map(&:meta))
            []
          end

          writer.write(trace)
          writer.stop

          expect(captured.size).to eq(1)
          expect(captured.first).not_to have_key("_dd.tracing.transport")
        end
      end

      context "with a supplied writer" do
        let(:custom) { instance_double(Datadog::Tracing::Writer, stop: true) }
        before { settings.tracing.writer = custom }

        it "bypasses built-in transport selection and formatting" do
          span = Datadog::Tracing::Span.new("root", id: 1, trace_id: 2, service: "app")
          trace = Datadog::Tracing::TraceSegment.new([span], id: 2, root_span_id: 1)
          expect(Datadog::Tracing::Component).not_to receive(:build_native_transport)
          expect(custom).to receive(:write).with(trace) do |segment|
            expect(segment.spans.first.meta).not_to have_key("_dd.tracing.transport")
          end

          writer.write(trace)
        end
      end
    end
  end

  describe ".default" do
    subject(:default) { described_class.default(agent_settings: default_agent_settings, logger: logger) }
    let(:default_agent_settings) do
      Datadog::Core::Configuration::AgentSettingsResolver.call(
        Datadog::Core::Configuration::Settings.new,
        logger: nil,
      )
    end

    # This test changes based on the environment tests are running. We have other
    # tests around each specific environment scenario, while this one specifically
    # ensures that we are matching the default environment settings.
    it "returns a transport with default configuration" do
      is_expected.to be_a_kind_of(Datadog::Tracing::Transport::Traces::Transport)
      expect(default.current_api_id).to eq("v0.4")

      expect(default.apis.keys).to eq(
        [
          "v0.4",
          "v0.3",
        ]
      )

      default.apis.each_value do |api|
        expect(api).to be_a_kind_of(Datadog::Core::Transport::HTTP::API::Instance)
        expect(api.headers).to include(Datadog::Core::Transport::HTTP.default_headers)

        case default_agent_settings.adapter
        when :net_http
          expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::Net)
          expect(api.adapter.hostname).to eq(default_agent_settings.hostname)
          expect(api.adapter.port).to eq(default_agent_settings.port)
          expect(api.adapter.ssl).to be(default_agent_settings.ssl)
        when :unix
          expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::UnixSocket)
          expect(api.adapter.filepath).to eq(default_agent_settings.uds_path)
        else
          raise("Unknown default adapter: #{default_agent_settings.adapter}")
        end
      end
    end

    context "when given an agent_settings" do
      subject(:default) { described_class.default(agent_settings: agent_settings, logger: logger, **options) }

      let(:options) { {} }

      let(:adapter) { :net_http }
      let(:ssl) { nil }
      let(:hostname) { nil }
      let(:port) { nil }
      let(:uds_path) { nil }
      let(:timeout_seconds) { nil }

      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettings.new(
          adapter: adapter,
          ssl: ssl,
          hostname: hostname,
          port: port,
          uds_path: uds_path,
          timeout_seconds: timeout_seconds
        )
      end

      context "that specifies host, port, timeout and ssl" do
        let(:hostname) { double("hostname") }
        let(:port) { double("port") }
        let(:timeout_seconds) { double("timeout") }
        let(:ssl) { true }

        it "returns a transport with provided options" do
          default.apis.each_value do |api|
            expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::Net)
            expect(api.adapter.hostname).to eq(hostname)
            expect(api.adapter.port).to eq(port)
            expect(api.adapter.timeout).to be(timeout_seconds)
            expect(api.adapter.ssl).to be true
          end
        end
      end
    end

    context "when given options" do
      subject(:default) { described_class.default(agent_settings: default_agent_settings, logger: logger, **options) }

      context "that specify headers" do
        let(:options) { {headers: headers} }
        let(:headers) { {"Test-Header" => "foo"} }

        it do
          default.apis.each_value do |api|
            expect(api.headers).to include(Datadog::Core::Transport::HTTP.default_headers)
            expect(api.headers).to include(headers)
          end
        end
      end
    end

    context "when given a block" do
      it do
        expect do |b|
          described_class.default(agent_settings: default_agent_settings, logger: logger, &b)
        end.to yield_with_args(
          kind_of(Datadog::Core::Transport::HTTP::Builder)
        )
      end
    end
  end
end
