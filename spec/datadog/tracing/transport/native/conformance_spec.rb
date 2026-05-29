# frozen_string_literal: true

require 'datadog/tracing/transport/native'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/transport/trace_formatter'
require 'socket'
require 'msgpack'

# Verifies that span data put into traces arrives on the wire (at the
# mock agent) with the correct field values after going through the
# full native transport path:
#
#   Ruby Span -> C extension -> Rust serialization -> msgpack -> HTTP -> mock agent
#
RSpec.describe 'Native transport wire-level conformance' do
  before do
    skip_if_libdatadog_not_supported
  end

  # ---------------------------------------------------------------------------
  # Capturing mock agent: runs in a fork, writes captured request bodies
  # to a pipe so the parent can read and deserialize them.
  # ---------------------------------------------------------------------------

  class CapturingMockAgent
    attr_reader :port

    def initialize
      @read_io, @write_io = IO.pipe
      server = TCPServer.new('127.0.0.1', 0)
      @port = server.addr[1]

      @pid = fork do
        @read_io.close

        body = '{"rate_by_service":{"service:,env:":1.0}}'
        http_response = "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n" \
                        "Content-Type: application/json\r\n\r\n#{body}"
        pipe_mutex = Mutex.new

        loop do
          client = server.accept rescue break
          Thread.new(client) do |c|
            begin
              request_line = c.gets
              next c.close if request_line.nil?

              # Read headers
              content_length = 0
              path = request_line.split(' ')[1]
              while (line = c.gets) && line != "\r\n"
                content_length = line.split(': ', 2).last.to_i if line.downcase.start_with?('content-length')
              end

              # Read body
              request_body = content_length > 0 ? c.read(content_length) : ''
              c.print http_response

              # Write captured trace payloads (skip /info requests)
              if path&.include?('/traces') && !request_body.empty?
                payload = Marshal.dump(request_body)
                pipe_mutex.synchronize do
                  @write_io.write([payload.bytesize].pack('N'))
                  @write_io.write(payload)
                  @write_io.flush
                end
              end
            rescue # rubocop:disable Lint/SuppressedException
            ensure
              c.close rescue nil
            end
          end
        end
      end

      server.close
      @write_io.close
    end

    # Read one captured trace payload (blocking, with timeout).
    # Returns the raw msgpack bytes.
    def read_payload(timeout: 5)
      ready = IO.select([@read_io], nil, nil, timeout)
      raise 'Timeout waiting for agent to receive a trace payload' unless ready

      len_bytes = @read_io.read(4)
      raise 'Agent pipe closed' if len_bytes.nil? || len_bytes.bytesize < 4

      len = len_bytes.unpack1('N')
      Marshal.load(@read_io.read(len)) # rubocop:disable Security/MarshalLoad
    end

    def stop
      Process.kill('TERM', @pid) rescue nil
      Process.wait(@pid) rescue nil
      @read_io.close rescue nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # A single mock agent and transport are shared across all examples.
  #
  # The Rust TraceExporter spawns background workers (e.g. /info fetcher)
  # that keep connections alive.  Creating one per test leaves orphaned
  # workers that interfere with subsequent tests. Using before/after(:all)
  # keeps everything scoped to this describe block.
  before(:all) do
    @mock_agent = CapturingMockAgent.new
    agent_settings = Struct.new(:url).new("http://127.0.0.1:#{@mock_agent.port}")
    @transport = Datadog::Tracing::Transport::Native::Transport.new(
      agent_settings: agent_settings,
      logger: Logger.new('/dev/null')
    )
  end

  after(:all) do
    # Release the transport reference and force GC so that
    # ddog_trace_exporter_free runs, shutting down the Rust
    # TraceExporter and its background workers (e.g. /info fetcher)
    # before we kill the mock agent process they connect to.
    @transport = nil
    GC.start
    @mock_agent&.stop
  end

  let(:mock_agent) { @mock_agent }
  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:transport) { @transport }

  def make_trace(spans_attrs)
    trace_id = rand(1 << 62)
    spans = spans_attrs.map do |attrs|
      Datadog::Tracing::Span.new(
        attrs[:name],
        service: attrs[:service] || 'conformance-svc',
        resource: attrs[:resource] || attrs[:name],
        type: attrs[:type],
        id: attrs[:id] || rand(1 << 62),
        parent_id: attrs[:parent_id] || 0,
        trace_id: attrs[:trace_id] || trace_id,
        status: attrs[:error] || 0,
      ).tap do |span|
        (attrs[:meta] || {}).each { |k, v| span.set_tag(k, v) }
        (attrs[:metrics] || {}).each { |k, v| span.set_metric(k, v) }
      end
    end
    Datadog::Tracing::TraceSegment.new(spans, id: trace_id, root_span_id: spans.first.id)
  end

  def send_and_decode(traces)
    responses = transport.send_traces(traces)
    expect(responses.first.ok?).to be(true), "send failed: #{responses.first.inspect}"

    raw = mock_agent.read_payload
    MessagePack.unpack(raw)
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe 'single span' do
    it 'preserves scalar fields on the wire' do
      trace = make_trace([{
        name: 'web.request',
        service: 'my-service',
        resource: 'GET /users',
        type: 'web',
        id: 12345,
        parent_id: 67890,
        error: 1,
      }])

      decoded = send_and_decode([trace])

      # v0.4 format: Array<Array<SpanHash>>
      expect(decoded).to be_an(Array)
      expect(decoded.length).to eq(1) # one trace chunk

      chunk = decoded.first
      expect(chunk.length).to eq(1) # one span

      span = chunk.first
      expect(span['name']).to eq('web.request')
      expect(span['service']).to eq('my-service')
      expect(span['resource']).to eq('GET /users')
      expect(span['type']).to eq('web')
      expect(span['span_id']).to eq(12345)
      expect(span['parent_id']).to eq(67890)
      expect(span['error']).to eq(1)
    end
  end

  describe 'meta and metrics' do
    it 'preserves string tags on the wire' do
      trace = make_trace([{
        name: 'op',
        meta: {
          'http.method' => 'POST',
          'http.url' => '/api/v1/traces',
          'component' => 'rack',
        },
      }])

      decoded = send_and_decode([trace])
      meta = decoded.first.first['meta']

      expect(meta['http.method']).to eq('POST')
      expect(meta['http.url']).to eq('/api/v1/traces')
      expect(meta['component']).to eq('rack')
    end

    it 'preserves numeric metrics on the wire' do
      trace = make_trace([{
        name: 'op',
        metrics: {
          '_dd.measured' => 1.0,
          '_sampling_priority_v1' => 2.0,
          'custom.metric' => 42.5,
        },
      }])

      decoded = send_and_decode([trace])
      metrics = decoded.first.first['metrics']

      expect(metrics['_dd.measured']).to eq(1.0)
      expect(metrics['_sampling_priority_v1']).to eq(2.0)
      expect(metrics['custom.metric']).to eq(42.5)
    end
  end

  describe 'trace ID' do
    it 'preserves 64-bit trace IDs' do
      tid = 0x00000000deadbeef
      trace = make_trace([{ name: 'op', trace_id: tid }])
      decoded = send_and_decode([trace])
      expect(decoded.first.first['trace_id']).to eq(tid)
    end

    it 'preserves the low 64 bits of 128-bit trace IDs' do
      low = 0xdeadbeef12345678
      high = 0x00000001
      tid = (high << 64) | low
      trace = make_trace([{ name: 'op', trace_id: tid }])
      decoded = send_and_decode([trace])

      # The wire format trace_id field is 64-bit (low half only);
      # high bits go into meta as _dd.p.tid
      expect(decoded.first.first['trace_id']).to eq(low)
    end
  end

  describe 'multiple spans in one trace' do
    it 'preserves all spans in a single chunk' do
      trace = make_trace([
        { name: 'parent.op', id: 100, parent_id: 0 },
        { name: 'child.op', id: 200, parent_id: 100 },
        { name: 'sibling.op', id: 300, parent_id: 100 },
      ])

      decoded = send_and_decode([trace])

      expect(decoded.length).to eq(1)
      names = decoded.first.map { |s| s['name'] }.sort
      expect(names).to eq(['child.op', 'parent.op', 'sibling.op'])
    end
  end

  describe 'multiple trace chunks' do
    it 'sends all chunks in one payload' do
      trace1 = make_trace([{ name: 'trace1.op' }])
      trace2 = make_trace([{ name: 'trace2.op' }])

      decoded = send_and_decode([trace1, trace2])

      expect(decoded.length).to eq(2)
      names = decoded.map { |chunk| chunk.first['name'] }.sort
      expect(names).to eq(['trace1.op', 'trace2.op'])
    end
  end
end
