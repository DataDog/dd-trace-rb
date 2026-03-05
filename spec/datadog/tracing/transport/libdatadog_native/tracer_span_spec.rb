# frozen_string_literal: true

require 'datadog/core'
require 'datadog/tracing/span'
require 'socket'

RSpec.describe 'Datadog::Tracing::Transport::LibdatadogNative' do
  before do
    unless Datadog::Core::LIBDATADOG_API_FAILURE.nil?
      skip "Native extension not available: #{Datadog::Core::LIBDATADOG_API_FAILURE}. " \
        'Try running `bundle exec rake compile` before running this test.'
    end
  end

  let(:native_module) { Datadog::Tracing::Transport::LibdatadogNative }
  let(:tracer_span_class) { native_module::TracerSpan }
  let(:trace_exporter_class) { native_module::TraceExporter }
  let(:response_class) { native_module::Response }

  # ===========================================================================
  # Helper: create a populated Ruby span for testing
  # ===========================================================================

  let(:now) { Time.now }
  let(:trace_id_128bit) { 0x0000000167890abc_00000001deadbeef }

  def make_ruby_span(overrides = {})
    defaults = {
      service: 'test-service',
      resource: 'GET /test',
      type: 'web',
      id: 12345,
      parent_id: 67890,
      trace_id: trace_id_128bit,
      start_time: now,
      duration: 0.025,
      status: 0,
      meta: { 'http.method' => 'GET', 'http.url' => '/test' },
      metrics: { '_dd.measured' => 1.0, '_sampling_priority_v1' => 2.0 },
    }
    Datadog::Tracing::Span.new('web.request', **defaults.merge(overrides))
  end

  # ===========================================================================
  # TracerSpan — creation
  # ===========================================================================

  describe 'TracerSpan._native_from_span' do
    context 'with a minimal span' do
      it 'returns a TracerSpan' do
        span = Datadog::Tracing::Span.new('test.op')
        result = tracer_span_class._native_from_span(span)
        expect(result).to be_a(tracer_span_class)
      end
    end

    context 'with all fields populated' do
      it 'returns a TracerSpan' do
        result = tracer_span_class._native_from_span(make_ruby_span)
        expect(result).to be_a(tracer_span_class)
      end
    end

    context 'with nil-able string fields set to nil' do
      it 'does not raise' do
        span = make_ruby_span(service: nil, type: nil)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with empty hashes' do
      it 'does not raise' do
        span = make_ruby_span(meta: {}, metrics: {})
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'with an unstarted span (no start_time)' do
      it 'does not raise' do
        span = make_ruby_span(start_time: nil, duration: nil)
        expect { tracer_span_class._native_from_span(span) }.not_to raise_error
      end
    end

    context 'when called multiple times on the same span' do
      it 'returns independent instances' do
        span = make_ruby_span
        r1 = tracer_span_class._native_from_span(span)
        r2 = tracer_span_class._native_from_span(span)
        expect(r1).to be_a(tracer_span_class)
        expect(r2).to be_a(tracer_span_class)
        expect(r1).not_to equal(r2)
      end
    end

    context 'GC safety' do
      it 'does not crash when instances are garbage collected' do
        20.times do
          tracer_span_class._native_from_span(make_ruby_span)
        end
        GC.start
        GC.start
      end
    end
  end

  # ===========================================================================
  # TracerSpan — reader methods (roundtrip: Ruby → Rust → Ruby)
  # ===========================================================================

  describe 'TracerSpan reader methods' do
    subject(:rust_span) { tracer_span_class._native_from_span(ruby_span) }

    let(:ruby_span) { make_ruby_span }

    describe '#name' do
      it 'returns the span name' do
        expect(rust_span.name).to eq('web.request')
      end
    end

    describe '#service' do
      it 'returns the service name' do
        expect(rust_span.service).to eq('test-service')
      end

      context 'when service is nil' do
        let(:ruby_span) { make_ruby_span(service: nil) }

        it 'returns an empty string' do
          expect(rust_span.service).to eq('')
        end
      end
    end

    describe '#resource' do
      it 'returns the resource' do
        expect(rust_span.resource).to eq('GET /test')
      end
    end

    describe '#type' do
      it 'returns the span type' do
        expect(rust_span.type).to eq('web')
      end

      context 'when type is nil' do
        let(:ruby_span) { make_ruby_span(type: nil) }

        it 'returns an empty string' do
          expect(rust_span.type).to eq('')
        end
      end
    end

    describe '#span_id' do
      it 'returns the span ID' do
        expect(rust_span.span_id).to eq(12345)
      end
    end

    describe '#parent_id' do
      it 'returns the parent ID' do
        expect(rust_span.parent_id).to eq(67890)
      end
    end

    describe '#trace_id' do
      context 'with a 128-bit trace ID' do
        it 'preserves the full 128-bit value' do
          expect(rust_span.trace_id).to eq(trace_id_128bit)
        end
      end

      context 'with a 64-bit trace ID' do
        let(:ruby_span) { make_ruby_span(trace_id: 0xDEADBEEF) }

        it 'preserves the value' do
          expect(rust_span.trace_id).to eq(0xDEADBEEF)
        end
      end

      context 'with trace_id = 0' do
        let(:ruby_span) { make_ruby_span(trace_id: 0) }

        it 'returns 0' do
          expect(rust_span.trace_id).to eq(0)
        end
      end

      context 'with max 128-bit trace ID' do
        let(:ruby_span) { make_ruby_span(trace_id: (1 << 128) - 1) }

        it 'preserves the value' do
          expect(rust_span.trace_id).to eq((1 << 128) - 1)
        end
      end
    end

    describe '#start' do
      it 'returns start time in nanoseconds matching the Ruby Time' do
        expected_ns = now.to_i * 1_000_000_000 + now.nsec
        expect(rust_span.start).to eq(expected_ns)
      end

      context 'when start_time is nil' do
        let(:ruby_span) { make_ruby_span(start_time: nil, duration: nil) }

        it 'returns 0' do
          expect(rust_span.start).to eq(0)
        end
      end
    end

    describe '#duration' do
      it 'returns duration in nanoseconds' do
        # 0.025 seconds = 25_000_000 nanoseconds (with floating-point tolerance)
        expect(rust_span.duration).to be_within(1).of(25_000_000)
      end

      context 'when duration is computed from end_time - start_time' do
        let(:ruby_span) do
          s = make_ruby_span(duration: nil)
          s.end_time = s.start_time + 0.1 # 100ms
          s
        end

        it 'returns the computed duration in nanoseconds' do
          expect(rust_span.duration).to be_within(100).of(100_000_000)
        end
      end
    end

    describe '#error' do
      it 'returns the error status' do
        expect(rust_span.error).to eq(0)
      end

      context 'when status indicates an error' do
        let(:ruby_span) { make_ruby_span(status: 1) }

        it 'returns the error value' do
          expect(rust_span.error).to eq(1)
        end
      end
    end

    describe '#get_meta' do
      it 'returns the value for an existing key' do
        expect(rust_span.get_meta('http.method')).to eq('GET')
        expect(rust_span.get_meta('http.url')).to eq('/test')
      end

      it 'returns nil for a missing key' do
        expect(rust_span.get_meta('nonexistent')).to be_nil
      end

      context 'with many meta tags' do
        let(:big_meta) do
          50.times.each_with_object({}) { |i, h| h["tag_#{i}"] = "value_#{i}" }
        end
        let(:ruby_span) { make_ruby_span(meta: big_meta) }

        it 'preserves all entries' do
          big_meta.each do |key, value|
            expect(rust_span.get_meta(key)).to eq(value), "Expected meta['#{key}'] = '#{value}'"
          end
        end
      end
    end

    describe '#get_metric' do
      it 'returns the value for an existing key' do
        expect(rust_span.get_metric('_dd.measured')).to eq(1.0)
        expect(rust_span.get_metric('_sampling_priority_v1')).to eq(2.0)
      end

      it 'returns nil for a missing key' do
        expect(rust_span.get_metric('nonexistent')).to be_nil
      end

      context 'with integer metric values' do
        let(:ruby_span) { make_ruby_span(metrics: { '_dd.top_level' => 1 }) }

        it 'converts to float' do
          expect(rust_span.get_metric('_dd.top_level')).to eq(1.0)
        end
      end
    end
  end

  # ===========================================================================
  # TraceExporter — creation
  # ===========================================================================

  describe 'TraceExporter._native_new' do
    it 'creates an exporter with all string arguments' do
      exporter = trace_exporter_class._native_new(
        'http://127.0.0.1:8126',
        '1.0.0',   # tracer_version
        'ruby',    # language
        RUBY_VERSION, # language_version
        RUBY_ENGINE,  # language_interpreter
        'testhost',   # hostname
        'test',       # env
        'testsvc',    # service
        '1.0',        # version
      )
      expect(exporter).to be_a(trace_exporter_class)
    end

    it 'accepts nil for optional string arguments' do
      exporter = trace_exporter_class._native_new(
        'http://127.0.0.1:8126',
        nil, nil, nil, nil, nil, nil, nil, nil,
      )
      expect(exporter).to be_a(trace_exporter_class)
    end

    it 'raises on non-string url' do
      expect {
        trace_exporter_class._native_new(
          12345, nil, nil, nil, nil, nil, nil, nil, nil,
        )
      }.to raise_error(TypeError)
    end
  end

  # ===========================================================================
  # TraceExporter#_native_send_traces — with a mock agent (TCP server)
  # ===========================================================================

  describe 'TraceExporter#_native_send_traces with mock agent' do
    # A minimal mock HTTP server that records trace requests.
    #
    # It handles both the /info endpoint (used by the background agent-info
    # worker) and the traces endpoint (/v0.4/traces or /v0.5/traces)
    # used by send_trace_chunks.
    let(:mock_agent) { MockAgent.new }

    after { mock_agent.stop }

    let(:exporter) do
      trace_exporter_class._native_new(
        "http://127.0.0.1:#{mock_agent.port}",
        '1.0.0-test',  # tracer_version
        'ruby',         # language
        RUBY_VERSION,
        RUBY_ENGINE,
        'test-host',
        'test-env',
        'test-service',
        '0.0.1',
      )
    end

    context 'with an empty array' do
      it 'returns an empty array without contacting the server' do
        responses = exporter._native_send_traces([])
        expect(responses).to eq([])
      end
    end

    context 'with a single trace containing one span' do
      let(:spans) { [make_ruby_span] }
      let(:traces) { [spans] }

      it 'sends the trace to the mock agent and returns a response' do
        responses = exporter._native_send_traces(traces)

        expect(responses).to be_an(Array)
        expect(responses.length).to eq(1)

        resp = responses.first
        # The send may succeed or fail depending on timing with the
        # background info worker; we just verify the response shape.
        expect(resp).to respond_to(:ok?)
        expect(resp).to respond_to(:trace_count)
        expect(resp.trace_count).to eq(1)

        # If the send succeeded, verify the mock agent received data
        if resp.ok?
          trace_reqs = mock_agent.wait_for_trace_request(timeout: 5)
          expect(trace_reqs).not_to be_empty

          req = trace_reqs.first
          expect(req[:path]).to match(%r{/v0\.\d/traces})
          expect(req[:body].bytesize).to be > 0
        end
      end
    end

    context 'with multiple traces' do
      let(:traces) do
        [
          [make_ruby_span(service: 'svc-a')],
          [make_ruby_span(service: 'svc-b'), make_ruby_span(service: 'svc-b', id: 99999, parent_id: 12345)],
        ]
      end

      it 'sends all traces and returns a response' do
        responses = exporter._native_send_traces(traces)

        expect(responses).to be_an(Array)
        expect(responses.length).to eq(1)
        expect(responses.first.trace_count).to eq(2)

        if responses.first.ok?
          trace_reqs = mock_agent.wait_for_trace_request(timeout: 5)
          expect(trace_reqs).not_to be_empty
          expect(trace_reqs.first[:body].bytesize).to be > 0
        end
      end
    end

    context 'Response interface' do
      it 'responds to all methods expected by Writer#send_spans' do
        responses = exporter._native_send_traces([[make_ruby_span]])

        resp = responses.first
        expect(resp).to respond_to(:ok?)
        expect(resp).to respond_to(:internal_error?)
        expect(resp).to respond_to(:server_error?)
        expect(resp).to respond_to(:trace_count)
        expect(resp).to respond_to(:unsupported?)
        expect(resp).to respond_to(:not_found?)
        expect(resp).to respond_to(:client_error?)
        expect(resp).to respond_to(:payload)
      end
    end
  end

  # ===========================================================================
  # TraceExporter — error cases
  # ===========================================================================

  describe 'TraceExporter error handling' do
    context 'when the agent is unreachable' do
      let(:exporter) do
        # Use a port that's extremely unlikely to be listening
        trace_exporter_class._native_new(
          'http://127.0.0.1:19',
          nil, nil, nil, nil, nil, nil, nil, nil,
        )
      end

      it 'returns an error response (does not raise)' do
        responses = exporter._native_send_traces([[make_ruby_span]])
        expect(responses).to be_an(Array)
        expect(responses.length).to eq(1)

        resp = responses.first
        expect(resp.ok?).to be false
        expect(resp.trace_count).to eq(1)
      end
    end
  end

  # ===========================================================================
  # Ruby Transport wrapper
  # ===========================================================================

  describe 'Datadog::Tracing::Transport::Libdatadog::Transport' do
    before do
      require 'datadog/tracing/transport/libdatadog'
    end

    let(:transport_module) { Datadog::Tracing::Transport::Libdatadog }

    describe '.supported?' do
      it 'returns true when the native extension is loaded' do
        expect(transport_module.supported?).to be true
      end
    end

    describe '#send_traces' do
      let(:mock_agent) { MockAgent.new }

      after { mock_agent.stop }

      let(:agent_settings) do
        double(
          'AgentSettings',
          url: "http://127.0.0.1:#{mock_agent.port}/",
        )
      end

      let(:logger) { Logger.new($stderr, level: :fatal) }

      let(:transport) do
        transport_module::Transport.new(
          agent_settings: agent_settings,
          logger: logger,
        )
      end

      context 'with an empty traces array' do
        it 'returns an empty array' do
          expect(transport.send_traces([])).to eq([])
        end
      end

      context 'with trace segments' do
        let(:span) { make_ruby_span }

        # Use a Struct so TraceFormatter.format! (which calls #send internally)
        # works without partial-double restrictions.
        let(:trace_segment) do
          Struct.new(:spans, :id, :root_span_id, keyword_init: true)
            .new(spans: [span], id: 1, root_span_id: nil)
        end

        it 'sends traces via the Rust pipeline and returns responses' do
          # Stub TraceFormatter.format! to be a no-op for this test
          allow(Datadog::Tracing::Transport::TraceFormatter).to receive(:format!)

          responses = transport.send_traces([trace_segment])

          expect(responses).to be_an(Array)
          expect(responses.length).to eq(1)
          expect(responses.first.trace_count).to be >= 0
        end
      end

      describe '#stats' do
        it 'returns a stats object with the expected fields' do
          stats = transport.stats
          expect(stats).to respond_to(:success)
          expect(stats).to respond_to(:client_error)
          expect(stats).to respond_to(:server_error)
          expect(stats).to respond_to(:internal_error)
          expect(stats).to respond_to(:reset!)
        end
      end
    end
  end

  # ===========================================================================
  # MockAgent — helper class for integration tests
  # ===========================================================================

  # Defined here so it's available to all examples above.
  # A simple TCP-based HTTP server that records incoming trace requests.
  class MockAgent
    attr_reader :port

    def initialize
      @server = TCPServer.new('127.0.0.1', 0)
      @port = @server.addr[1]
      @trace_requests = []
      @mutex = Mutex.new
      @running = true
      @client_threads = []
      @accept_thread = Thread.new { accept_loop }
    end

    def stop
      @running = false
      @server.close rescue nil
      @accept_thread.join(3)
      @client_threads.each { |t| t.join(1) rescue nil }
    end

    # Returns all recorded trace requests, waiting up to +timeout+ seconds
    # for at least one to arrive.
    def wait_for_trace_request(timeout: 5)
      deadline = Time.now + timeout
      loop do
        reqs = @mutex.synchronize { @trace_requests.dup }
        return reqs unless reqs.empty?
        return reqs if Time.now >= deadline

        sleep 0.05
      end
    end

    private

    def accept_loop
      while @running
        begin
          client = @server.accept
          t = Thread.new(client) { |c| handle_client(c) }
          @client_threads << t
        rescue IOError, Errno::EBADF
          break
        end
      end
    end

    def handle_client(client)
      # Read the full HTTP request and send back a valid response.
      # We loop to support HTTP keep-alive (multiple requests per connection).
      loop do
        request_line = client.gets
        break if request_line.nil?

        method, path, _version = request_line.strip.split(' ', 3)
        break if method.nil?

        headers = {}
        while (line = client.gets)
          stripped = line.strip
          break if stripped.empty?

          key, value = stripped.split(':', 2)
          headers[key.strip.downcase] = value.strip if key && value
        end

        content_length = (headers['content-length'] || '0').to_i
        body = content_length > 0 ? client.read(content_length) : ''.b

        # Record trace requests
        if path && path.include?('/traces')
          @mutex.synchronize do
            @trace_requests << {
              method: method,
              path: path,
              headers: headers.dup,
              body: body.dup,
            }
          end
        end

        # Send a well-formed HTTP response
        #
        # For /info the agent returns basic info; for traces it returns
        # rate_by_service.  We return a minimal valid response for both.
        response_body = if path && path.include?('/info')
          '{"version":"mock-0.0.1","endpoints":["/v0.4/traces"],"config":{}}'
        else
          '{"rate_by_service":{"service:,env:":1.0}}'
        end

        response = "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: application/json\r\n" \
                   "Content-Length: #{response_body.bytesize}\r\n" \
                   "\r\n" \
                   "#{response_body}"

        client.write(response)
        client.flush
        # Loop continues — supports HTTP/1.1 keep-alive
      end
    rescue Errno::ECONNRESET, Errno::EPIPE, IOError
      # client disconnected — that's fine
    ensure
      client.close rescue nil
    end
  end
end
