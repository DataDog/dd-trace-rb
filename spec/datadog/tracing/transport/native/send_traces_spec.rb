# frozen_string_literal: true

require 'datadog/core'
require 'datadog/tracing/span'
require 'socket'
require 'json'

RSpec.describe 'Datadog::Tracing::Transport::Native::TraceExporter#_native_send_traces' do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:trace_exporter_class) { native_module::TraceExporter }
  let(:response_class) { native_module::Response }

  # ---------------------------------------------------------------------------
  # Minimal mock HTTP agent (TCP server)
  #
  # Accepts connections, reads the HTTP request, and replies with a
  # configurable status and body.  Handles both /info (used by the
  # background agent-info worker) and trace endpoints.
  # ---------------------------------------------------------------------------

  class MockAgent
    attr_reader :port, :requests

    def initialize(status: 200, body: '{"rate_by_service":{"service:,env:":1.0}}')
      @status = status
      @body = body
      @requests = []
      @server = TCPServer.new('127.0.0.1', 0)
      @port = @server.addr[1]
      @thread = Thread.new { run }
    end

    def stop
      @running = false
      @server.close rescue nil
      @thread.join(2)
    end

    private

    def run
      @running = true
      while @running
        client = @server.accept rescue break
        handle(client)
      end
    end

    def handle(client)
      request_line = client.gets
      return client.close if request_line.nil?

      headers = {}
      while (line = client.gets) && line != "\r\n"
        key, value = line.split(': ', 2)
        headers[key.downcase] = value&.strip
      end

      body_len = (headers['content-length'] || 0).to_i
      body = body_len > 0 ? client.read(body_len) : ''

      @requests << { request_line: request_line.strip, headers: headers, body: body }

      response_body = @body
      client.print "HTTP/1.1 #{@status} OK\r\n"
      client.print "Content-Length: #{response_body.bytesize}\r\n"
      client.print "Content-Type: application/json\r\n"
      client.print "\r\n"
      client.print response_body
      client.close
    rescue => e
      $stderr.puts "MockAgent error: #{e}" if ENV['DEBUG']
      client&.close
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  let(:mock_agent) { MockAgent.new }
  after { mock_agent.stop }

  let(:exporter) do
    trace_exporter_class._native_new(
      "http://127.0.0.1:#{mock_agent.port}",
      '1.0.0-test',
      'ruby',
      RUBY_VERSION,
      RUBY_ENGINE,
      'test-host',
      'test-env',
      'test-service',
      '0.0.1',
    )
  end

  def make_span(name = 'test.op', **overrides)
    defaults = {
      service: 'test-svc',
      resource: 'GET /test',
      type: 'web',
      id: rand(1 << 62),
      parent_id: 0,
      trace_id: rand(1 << 62),
    }
    Datadog::Tracing::Span.new(name, **defaults.merge(overrides))
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe 'with an empty array' do
    it 'returns an empty array without contacting the server' do
      responses = exporter._native_send_traces([])
      expect(responses).to eq([])
    end
  end

  describe 'with a single trace containing one span' do
    it 'returns a success response' do
      spans = [make_span]
      responses = exporter._native_send_traces([spans])

      expect(responses).to be_an(Array)
      expect(responses.length).to eq(1)

      resp = responses.first
      expect(resp).to be_a(response_class)
      expect(resp.ok?).to be true
      expect(resp.internal_error?).to be false
      expect(resp.server_error?).to be false
      expect(resp.trace_count).to eq(1)
    end

    it 'returns a payload with the agent response body' do
      spans = [make_span]
      responses = exporter._native_send_traces([spans])
      resp = responses.first

      # The payload should contain the mock agent's JSON body
      expect(resp.payload).to be_a(String)
      parsed = JSON.parse(resp.payload)
      expect(parsed).to have_key('rate_by_service')
    end
  end

  describe 'with multiple trace chunks' do
    it 'sends all chunks and returns a success response' do
      chunk1 = [make_span('op1'), make_span('op2')]
      chunk2 = [make_span('op3')]
      responses = exporter._native_send_traces([chunk1, chunk2])

      expect(responses.length).to eq(1)
      expect(responses.first.ok?).to be true
      expect(responses.first.trace_count).to eq(2)
    end
  end

  describe 'with spans containing meta and metrics' do
    it 'does not raise' do
      span = make_span
      span.set_tag('http.method', 'GET')
      span.set_tag('http.url', '/test')
      span.set_metric('_dd.measured', 1.0)

      responses = exporter._native_send_traces([[span]])
      expect(responses.first.ok?).to be true
    end
  end

  describe 'when the agent returns an error' do
    let(:mock_agent) { MockAgent.new(status: 500, body: '{"error":"server overloaded"}') }

    it 'returns an error response' do
      responses = exporter._native_send_traces([[make_span]])

      expect(responses.length).to eq(1)
      resp = responses.first
      expect(resp.ok?).to be false
      # The error should be classified as server or internal
      expect(resp.server_error? || resp.internal_error?).to be true
    end
  end

  describe 'argument validation' do
    it 'raises TypeError for non-array argument' do
      expect { exporter._native_send_traces('not an array') }.to raise_error(TypeError)
    end

    it 'raises TypeError for non-array inner element' do
      expect { exporter._native_send_traces(['not an array']) }.to raise_error(TypeError)
    end
  end
end
