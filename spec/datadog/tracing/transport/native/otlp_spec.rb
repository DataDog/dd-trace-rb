# frozen_string_literal: true

require "datadog/tracing/transport/native"
require "datadog/tracing/span"
require "datadog/tracing/trace_segment"
require "json"
require "socket"

class NativeOtlpCaptureServer
  attr_reader :port

  def initialize(response_body: "")
    @response_body = response_body
    @requests = []
    @requests_mutex = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { run }
  end

  def requests
    @requests_mutex.synchronize { @requests.dup }
  end

  def stop
    @server.close
  rescue IOError
    nil
  ensure
    @thread.join(2)
  end

  private

  def run
    loop do
      client = @server.accept
      handle(client)
    rescue IOError, Errno::EBADF
      break
    end
  end

  def handle(client)
    request_line = client.gets
    return if request_line.nil?

    headers = {}
    while (line = client.gets) && line != "\r\n"
      key, value = line.split(": ", 2)
      headers[key.downcase] = value&.strip
    end

    content_length = (headers["content-length"] || 0).to_i
    body = content_length.zero? ? "" : client.read(content_length)
    @requests_mutex.synchronize do
      @requests << {request_line: request_line.strip, headers: headers, body: body}
    end

    client.print "HTTP/1.1 200 OK\r\n"
    client.print "Content-Length: #{@response_body.bytesize}\r\n"
    client.print "Content-Type: application/json\r\n\r\n"
    client.print @response_body
  ensure
    client.close
  end
end

RSpec.describe "Native OTLP trace export" do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:collector) { NativeOtlpCaptureServer.new }
  let(:agent) { NativeOtlpCaptureServer.new(response_body: '{"endpoints":["v0.4/traces"]}') }
  let(:agent_settings) { double("agent_settings", url: "http://127.0.0.1:#{agent.port}") }
  let(:logger) { Logger.new(File::NULL) }
  let(:built_transports) { [] }

  after do
    built_transports.each { |transport| NativeTransportForkIsolation.dispose(transport) }
    collector.stop
    agent.stop
  end

  def build_transport(protocol)
    Datadog::Tracing::Transport::Native::Transport.new(
      agent_settings: agent_settings,
      logger: logger,
      otlp_endpoint: "http://127.0.0.1:#{collector.port}/v1/traces",
      otlp_headers: {"authorization" => "Bearer test", "x-test-route" => "ruby"},
      otlp_timeout_millis: 2500,
      otlp_protocol: protocol
    ).tap { |transport| built_transports << transport }
  end

  def make_trace(resource:, sampling_priority: 2, child: false)
    trace_id = (0x1234567890ABCDEF << 64) | 0x1020304050607080
    root = Datadog::Tracing::Span.new(
      "rack.request",
      service: "native-otlp-test",
      resource: resource,
      type: "web",
      id: 0x1122334455667788,
      parent_id: 0,
      trace_id: trace_id
    )
    spans = [root]
    if child
      spans << Datadog::Tracing::Span.new(
        "child.operation",
        service: "native-otlp-test",
        resource: "child.resource",
        id: 0x2233445566778899,
        parent_id: root.id,
        trace_id: trace_id
      )
    end

    Datadog::Tracing::TraceSegment.new(
      spans,
      id: trace_id,
      root_span_id: root.id,
      sampling_priority: sampling_priority
    )
  end

  def trace_posts(server)
    server.requests.select { |request| request[:request_line].match?(%r{\APOST /v\d+(?:\.\d+)?/traces }) }
  end

  it "exports HTTP/JSON with configured headers and a 128-bit trace ID" do
    response = build_transport("http/json").send_traces([
      make_trace(resource: "json.resource", child: true),
    ]).first

    expect(response).to be_ok
    request = collector.requests.fetch(0)
    expect(request[:request_line]).to start_with("POST /v1/traces ")
    expect(request[:headers]).to include(
      "content-type" => "application/json",
      "authorization" => "Bearer test",
      "x-test-route" => "ruby"
    )

    payload = JSON.parse(request[:body])
    expect(payload.fetch("resourceSpans").length).to eq(1)
    spans = payload.dig("resourceSpans", 0, "scopeSpans", 0, "spans")
    expect(spans.map { |span| span.fetch("name") }).to contain_exactly("json.resource", "child.resource")
    expect(spans.map { |span| span.fetch("traceId") }.uniq)
      .to eq(["1234567890abcdef1020304050607080"])
    expect(trace_posts(agent)).to be_empty
  end

  it "exports HTTP/protobuf" do
    response = build_transport("http/protobuf").send_traces([
      make_trace(resource: "protobuf.resource"),
    ]).first

    expect(response).to be_ok
    request = collector.requests.fetch(0)
    expect(request[:headers]["content-type"]).to eq("application/x-protobuf")
    expect(request[:body]).to start_with("\x0A".b)
    expect(request[:body]).to include("protobuf.resource")
    expect(trace_posts(agent)).to be_empty
  end

  it "falls back to HTTP/protobuf while grpc is unsupported" do
    response = build_transport("grpc").send_traces([
      make_trace(resource: "grpc-fallback.resource"),
    ]).first

    expect(response).to be_ok
    request = collector.requests.fetch(0)
    expect(request[:headers]["content-type"]).to eq("application/x-protobuf")
    expect(request[:body]).to include("grpc-fallback.resource")
  end

  it "does not export a rejected trace" do
    response = build_transport("http/protobuf").send_traces([
      make_trace(resource: "rejected.resource", sampling_priority: -1),
    ]).first

    expect(response).to be_ok
    expect(collector.requests).to be_empty
    expect(trace_posts(agent)).to be_empty
  end
end
