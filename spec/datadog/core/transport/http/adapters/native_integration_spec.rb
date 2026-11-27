require "spec_helper"

require "json"
require "socket"
require "stringio"
require "tmpdir"
require "timeout"
require "datadog/core/utils/at_fork_monkey_patch"
require "datadog/core/transport/http/env"
require "datadog/core/transport/http/adapters/native"
require "datadog/core/vendor/multipart-post/multipart/post/composite_read_io"

# Integration tests for the native HTTP adapter: the whole path
#
#   Adapter -> C extension -> Rust HTTP client -> mock agent
#
# The native client speaks HTTP from Rust, so WebMock does not see it. The mock agent runs in a forked process
# (so no Ruby acceptor threads leak into this one).
#
# They need the `libdatadog_api` extension built with a libdatadog that includes the HTTP client, and they fork
# with live native clients, so they run in their own task (`rake spec:native_http`, see NATIVE_HTTP_SPECS).
RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Native, :native_http do
  before do
    skip_if_libdatadog_not_supported
    skip "The libdatadog in use does not include the native HTTP client" unless described_class.supported?
  end

  # Answers requests, by path:
  # * `/echo`: 200 with a JSON description of the request;
  # * `/status/<code>`: that status, with the body "status <code>";
  # * `/binary`: every byte value, in order;
  # * `/hold`: tells the parent that it arrived (through a pipe), and never answers.
  class NativeHttpMockAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port, :socket_path

    def initialize(unix: false)
      @arrived_read, @arrived_write = IO.pipe

      if unix
        @socket_path = File.join(Dir.mktmpdir("native-http"), "agent.sock")
        server = UNIXServer.new(@socket_path)
      else
        server = TCPServer.new("127.0.0.1", 0)
        @port = server.addr[1]
      end

      @pid = fork do
        @arrived_read.close
        held = []
        loop do
          client = begin
            server.accept
          rescue
            break
          end
          Thread.new(client) { |c| serve(c, held) }
        end
      end

      server.close
      @arrived_write.close
    end

    def base_url
      "http://127.0.0.1:#{port}"
    end

    # Blocks until a `/hold` request arrived: the send is then in flight.
    def wait_for_hold(timeout: 5)
      raise "Timed out waiting for the request to reach the mock agent" unless IO.select([@arrived_read], nil, nil, timeout)

      @arrived_read.read(1)
    end

    def stop
      NativeTransportForkIsolation.reap_process(@pid)
      @arrived_read.close
      FileUtils.rm_rf(File.dirname(@socket_path)) if @socket_path
    end

    private

    def serve(client, held)
      request_line = client.gets
      return client.close if request_line.nil?

      headers = {}
      while (line = client.gets) && line != "\r\n"
        name, value = line.chomp.split(": ", 2)
        headers[name.downcase] = value
      end
      body = headers["content-length"] ? client.read(headers["content-length"].to_i) : +""

      verb, path, = request_line.split(" ")
      case path
      when %r{\A/status/(\d+)}
        respond(client, Regexp.last_match(1).to_i, "status #{Regexp.last_match(1)}", "Content-Type" => "text/plain")
      when "/binary"
        respond(client, 200, (0..255).map(&:chr).join.b, "Content-Type" => "application/octet-stream")
      when "/hold"
        held << client # never answered, and kept open
        @arrived_write.write("x")
      else
        echo = {verb: verb, path: path, headers: headers, body_base64: [body].pack("m0")}
        respond(client, 200, JSON.generate(echo), "Content-Type" => "application/json", "X-Mock" => "yes")
      end
    rescue
      client.close unless client.closed?
    end

    def respond(client, status, body, headers = {})
      head = headers.map { |name, value| "#{name}: #{value}\r\n" }.join
      client.write("HTTP/1.1 #{status} Status\r\nContent-Length: #{body.bytesize}\r\n#{head}Connection: close\r\n\r\n")
      client.write(body)
      client.close
    end
  end

  let(:agent) { NativeHttpMockAgent.new }
  let(:timeout) { 5 }
  let(:adapter) { described_class.new(base_url: agent.base_url, timeout: timeout) }

  let(:verb) { :get }
  let(:path) { "/echo" }
  let(:query) { nil }
  let(:body) { nil }
  let(:headers) { {} }
  let(:form) { nil }
  let(:env) do
    Datadog::Core::Transport::HTTP::Env.new(double("request")).tap do |env|
      env.verb = verb
      env.path = path
      env.query = query
      env.body = body
      env.headers = headers
      env.form = form
    end
  end

  def echoed(response)
    JSON.parse(response.payload).tap { |echo| echo["body"] = echo.delete("body_base64").unpack1("m") }
  end

  before(:all) { Datadog::Core::Utils::AtForkMonkeyPatch.apply! }

  after do
    adapter.close
    agent.stop
  end

  describe "over TCP" do
    context "with a POST" do
      let(:verb) { :post }
      let(:path) { "/echo" }
      let(:query) { {"a" => "1 2", "b" => "c"} }
      let(:body) { "payload ☃".b }
      let(:headers) { {"X-Test" => "value", "Content-Type" => "application/octet-stream"} }

      it "sends the verb, path, query, headers and body" do
        response = adapter.call(env)

        expect(response).to be_ok
        echo = echoed(response)
        expect(echo).to include("verb" => "POST", "path" => "/echo?a=1+2&b=c", "body" => "payload ☃".b)
        expect(echo["headers"]).to include("x-test" => "value", "content-type" => "application/octet-stream")
      end
    end

    %i[get put delete patch options].each do |http_verb|
      context "with #{http_verb.to_s.upcase}" do
        let(:verb) { http_verb }

        it "sends the verb" do
          expect(echoed(adapter.call(env))).to include("verb" => http_verb.to_s.upcase)
        end
      end
    end

    context "with HEAD" do
      let(:verb) { :head }

      it "gets the status and headers, and no body" do
        response = adapter.call(env)

        expect(response).to be_ok
        expect(response.headers).to include("x-mock" => "yes")
        expect(response.payload).to eq("")
      end
    end

    context "with a large body" do
      let(:verb) { :post }
      let(:body) { "x" * 3_000_000 }

      it "sends all of it" do
        expect(echoed(adapter.call(env))["body"].bytesize).to eq(3_000_000)
      end
    end

    context "with a multipart form" do
      let(:verb) { :post }
      let(:form) do
        io = StringIO.new("{}")
        io.read # consumed: the adapter must rewind it
        {
          "event" => Datadog::Core::Vendor::Multipart::Post::UploadIO.new(io, "application/json", "event.json"),
          "note" => "text",
        }
      end

      it "sends the parts" do
        echo = echoed(adapter.call(env))

        expect(echo["headers"]["content-type"]).to start_with("multipart/form-data; boundary=")
        expect(echo["body"]).to include('name="event"; filename="event.json"', "Content-Type: application/json", "{}")
        expect(echo["body"]).to include('name="note"', "text")
      end
    end

    describe "the response" do
      it "has lowercased header names" do
        expect(adapter.call(env).headers).to include("content-type" => "application/json", "x-mock" => "yes")
      end

      context "with a binary body" do
        let(:path) { "/binary" }

        it "returns all the bytes" do
          payload = adapter.call(env).payload

          expect(payload.bytes).to eq((0..255).to_a)
          expect(payload.encoding).to eq(Encoding::BINARY)
        end
      end

      {
        404 => :not_found?,
        415 => :unsupported?,
        500 => :server_error?,
      }.each do |status, predicate|
        context "with status #{status}" do
          let(:path) { "/status/#{status}" }

          it "is a response, not an error" do
            response = adapter.call(env)

            expect(response.code).to eq(status)
            expect(response.public_send(predicate)).to be(true)
            expect(response).not_to be_ok
            expect(response.payload).to eq("status #{status}")
          end
        end
      end
    end

    describe "errors" do
      it "raises an error when the connection is refused" do
        unused_port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
        adapter = described_class.new(base_url: "http://127.0.0.1:#{unused_port}", timeout: timeout)

        expect { adapter.call(env) }.to raise_error(described_class::Error) { |e| expect(e.code).to eq(:connection_failed) }
      ensure
        adapter&.close
      end

      context "when the agent does not answer in time" do
        let(:path) { "/hold" }
        let(:timeout) { 0.3 }

        it "raises a timeout error" do
          expect { adapter.call(env) }.to raise_error(described_class::Error) { |e| expect(e.code).to eq(:timed_out) }
        end
      end

      it "rejects an unknown verb" do
        env.verb = :bogus

        expect { adapter.call(env) }.to raise_error(ArgumentError, /Unknown HTTP verb/)
      end
    end

    describe "interrupting a request in flight" do
      let(:path) { "/hold" }
      let(:timeout) { 30 }

      def finishes_quickly(thread)
        expect(thread.join(5)).to eq(thread), "the blocked request was not interrupted"
      end

      it "is cancelled by Thread#kill, and the adapter keeps working" do
        thread = Thread.new { adapter.call(env) }
        agent.wait_for_hold

        thread.kill
        finishes_quickly(thread)

        env.path = "/echo"
        expect(adapter.call(env)).to be_ok
      end

      it "is cancelled by Timeout, and the adapter keeps working" do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect { Timeout.timeout(0.3) { adapter.call(env) } }.to raise_error(Timeout::Error)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5

        env.path = "/echo"
        expect(adapter.call(env)).to be_ok
      end

      it "does not block the other Ruby threads" do
        thread = Thread.new { adapter.call(env) }
        agent.wait_for_hold

        expect(Timeout.timeout(2) { 1 + 1 }).to eq(2)
        expect(Thread.new { :other }.value).to eq(:other)
      ensure
        thread&.kill
        thread&.join(5)
      end
    end

    describe "#close" do
      it "makes later requests raise" do
        adapter.close

        expect { adapter.call(env) }.to raise_error(described_class::Error, /closed/)
      end

      it "waits for the request in flight" do
        env.path = "/hold"
        request = Thread.new do
          Thread.current.report_on_exception = false
          adapter.call(env)
        end
        agent.wait_for_hold

        closing = Thread.new { adapter.close }
        Thread.pass until closing.status == "sleep"
        expect(closing).to be_alive

        request.kill
        request.join(5)
        expect(closing.join(5)).to eq(closing)
      end
    end
  end

  describe "over a Unix socket" do
    let(:agent) { NativeHttpMockAgent.new(unix: true) }
    let(:adapter) { described_class.new(base_url: nil, timeout: timeout, uds_path: agent.socket_path) }

    let(:verb) { :post }
    let(:query) { {"a" => "1"} }
    let(:body) { "through the socket" }

    it "sends the request" do
      response = adapter.call(env)

      expect(response).to be_ok
      expect(echoed(response)).to include("verb" => "POST", "path" => "/echo?a=1", "body" => "through the socket")
    end

    context "with a status other than 200" do
      let(:path) { "/status/404" }

      it "returns it as a response" do
        expect(adapter.call(env)).to be_not_found
      end
    end
  end

  describe "the runtime" do
    def thread_count
      File.read("/proc/self/status")[/^Threads:\s+(\d+)/, 1].to_i
    end

    it "is shared by all the clients" do
      skip "Needs /proc" unless File.exist?("/proc/self/status")

      adapter.call(env) # the runtime exists from now on
      before = thread_count

      adapters = Array.new(10) { described_class.new(base_url: agent.base_url, timeout: timeout) }
      begin
        adapters.each { |other| expect(other.call(env)).to be_ok }

        # A runtime per client would add, at least, one thread per client.
        expect(thread_count - before).to be < 5
      ensure
        adapters.each(&:close)
      end
    end
  end

  describe "forking" do
    before { skip "Fork not supported on this platform" unless Process.respond_to?(:fork) }

    it "keeps working in the parent and in the child" do
      expect(adapter.call(env)).to be_ok

      child = fork do
        # Only exit statuses are used to report: no RSpec in the child.
        exit!(begin
          response = adapter.call(env)
          (response.ok? && JSON.parse(response.payload)["verb"] == "GET") ? 0 : 2
        rescue => e
          warn("child failed: #{e.class}: #{e.message}")
          3
        end)
      end

      _, status = Timeout.timeout(20) { Process.wait2(child) }
      expect(status.exitstatus).to eq(0)

      expect(adapter.call(env)).to be_ok
    end

    it "keeps working after several forks, with several clients" do
      adapters = [adapter, described_class.new(base_url: agent.base_url, timeout: timeout)]
      adapters.each { |each| expect(each.call(env)).to be_ok }

      3.times do
        child = fork { exit!((adapters.all? { |each| each.call(env).ok? }) ? 0 : 1) }
        _, status = Timeout.timeout(20) { Process.wait2(child) }
        expect(status.exitstatus).to eq(0)
      end

      adapters.each { |each| expect(each.call(env)).to be_ok }
    ensure
      adapters&.last&.close
    end
  end
end
