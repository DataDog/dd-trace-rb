require "datadog/tracing/contrib/integration_examples"
require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/analytics_examples"
require "datadog/tracing/contrib/environment_service_name_examples"
require "datadog/tracing/contrib/span_attribute_schema_examples"
require "datadog/tracing/contrib/peer_service_configuration_examples"
require "datadog/tracing/contrib/svc_src_examples"

require "datadog"
require "net/http"

RSpec.describe "net/http connections" do
  http_server do |server|
    server.mount_proc("/") { |_request, response| response.status = 200 }
  end

  let(:host) { "127.0.0.1" }
  let(:port) { http_server_port }
  let(:client) { Net::HTTP.new(host, port) }
  let(:configuration_options) { {} }
  let(:connect_span) { spans.find { |span| span.name == "http.connect" } }

  # The integration patches whichever class `Net::HTTP` refers to, which may be
  # WebMock's replacement class. WebMock's `Net::HTTP#start` connects only when
  # `net_http_connect_on_start` is set.
  before do
    WebMock.enable!
    WebMock.allow_net_connect!(net_http_connect_on_start: true)
  end

  after do
    WebMock.allow_net_connect!
    WebMock.reset!
    WebMock.disable!
  end

  before do
    Datadog.configure { |c| c.tracing.instrument :http, configuration_options }
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:http].reset_configuration!
    example.run
    Datadog.registry[:http].reset_configuration!
  end

  after { client.finish if client.started? }

  it "keeps Net::HTTP#connect private" do
    expect(Net::HTTP.private_method_defined?(:connect)).to be true
  end

  context "when a trace is active" do
    subject(:connection) { Datadog::Tracing.trace("parent") { client.start } }

    let(:parent_span) { spans.find { |span| span.name == "parent" } }

    it "traces the connection as a child of the active span" do
      connection

      expect(spans).to have(2).items
      expect(connect_span.parent_id).to eq(parent_span.id)
      expect(connect_span.service).to eq("net/http")
      expect(connect_span.resource).to eq("127.0.0.1")
      expect(connect_span.type).to eq("http")
      expect(connect_span.get_tag("span.kind")).to eq("client")
      expect(connect_span.get_tag("component")).to eq("net/http")
      expect(connect_span.get_tag("operation")).to eq("connect")
      expect(connect_span.get_tag("out.host")).to eq("127.0.0.1")
      expect(connect_span.get_tag("out.port")).to eq(port.to_s)
      expect(connect_span.get_tag("peer.hostname")).to eq("127.0.0.1")
      expect(connect_span.status).to eq(0)
    end

    context "with the span under test being the connect span" do
      let(:span) { connect_span }

      it_behaves_like "tags _dd.svc_src", "net/http" do
        before { connection }
      end

      it_behaves_like "analytics for integration" do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::HTTP::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::HTTP::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        before { connection }
      end

      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "127.0.0.1" }
        let(:peer_service_source) { "peer.hostname" }
      end

      it_behaves_like "environment service name", "DD_TRACE_NET_HTTP_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_NET_HTTP_PEER_SERVICE"
      it_behaves_like "schema version span"
    end

    context "with split_by_domain enabled" do
      let(:configuration_options) { {split_by_domain: true} }

      it "uses the host as the service name" do
        connection

        expect(connect_span.service).to eq("127.0.0.1")
      end
    end

    context "with a service name configured onto the client" do
      before { Datadog.configure_onto(client, service_name: "client-service") }

      it "uses the client service name" do
        connection

        expect(connect_span.service).to eq("client-service")
      end
    end

    context "when the connection is refused" do
      let(:port) { available_port }

      it "marks the connect span as an error and raises the connection error" do
        expect { connection }.to raise_error(Errno::ECONNREFUSED)

        expect(connect_span).to have_error
        expect(connect_span.get_tag("error.type")).to eq("Errno::ECONNREFUSED")
      end
    end

    context "when annotating the connect span fails" do
      before do
        allow(Datadog::Tracing::Contrib::SpanAttributeSchema).to receive(:set_peer_service!)
          .and_raise(StandardError, "annotation failure")
        allow(Datadog.logger).to receive(:error)
        allow(Datadog::Core::Telemetry::Logger).to receive(:report)
      end

      it "connects, logs the error and reports it to telemetry" do
        connection

        expect(connect_span).to_not be_nil
        expect(Datadog.logger).to have_received(:error)
          .with("error preparing span from http connection: StandardError: annotation failure")
        expect(Datadog::Core::Telemetry::Logger).to have_received(:report)
          .with(an_instance_of(StandardError))
      end
    end
  end

  context "when the client sends a request without being started" do
    subject(:response) { client.get("/") }

    let(:request_span) { spans.find { |span| span.name == "http.request" } }

    it "traces the connection as a child of the request span" do
      expect(response.code).to eq("200")

      expect(spans).to have(2).items
      expect(connect_span.parent_id).to eq(request_span.id)
    end
  end

  context "when no trace is active" do
    subject(:connection) { client.start }

    it "connects without creating a span" do
      expect { connection }.to change(client, :started?).from(false).to(true)

      expect(spans).to be_empty
    end
  end

  context "when the active trace is finished" do
    subject(:connection) { client.start }

    let(:finished_trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: true) }

    before { allow(Datadog::Tracing).to receive(:active_trace).and_return(finished_trace) }

    it "connects without creating a span" do
      expect(Datadog::Tracing).to_not receive(:trace)

      expect { connection }.to change(client, :started?).from(false).to(true)

      expect(spans).to be_empty
    end
  end
end
