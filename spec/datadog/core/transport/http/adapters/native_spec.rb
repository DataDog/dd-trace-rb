require "spec_helper"

require "stringio"
require "uri"
require "datadog/core/configuration/agent_settings"
require "datadog/core/configuration/ext"
require "datadog/core/transport/http/env"
require "datadog/core/transport/http/adapters/native"
require "datadog/core/vendor/multipart-post/multipart/post/composite_read_io"

RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Native do
  subject(:adapter) { described_class.new(base_url: base_url, timeout: 5, uds_path: uds_path, client: client) }

  let(:base_url) { "http://agent:8126/" }
  let(:uds_path) { nil }
  let(:client) { double("native client", _native_send: result, _native_close: nil) }
  let(:client_class) { double("native client class", _native_new: client) }
  let(:result) { [:ok, 200, [], ""] }

  # These specs do not need the C extension: `Native::Client` is replaced by a double.
  before do
    stub_const("Datadog::Core::Transport::HTTP::Adapters::Native::Client", client_class)
    allow(Datadog::Core::Transport::HTTP::Adapters::Native)
      .to receive_messages(unsupported_reason: nil, register_fork_hooks: true)
  end

  let(:env) do
    Datadog::Core::Transport::HTTP::Env.new(double("request")).tap do |env|
      env.verb = :post
      env.path = "/v0.7/config"
      env.body = "payload"
      env.headers = {"X-A" => "1"}
    end
  end

  describe "#initialize" do
    it "removes the trailing slash of the base URL" do
      expect(adapter.base_url).to eq("http://agent:8126")
    end

    context "with a Unix socket" do
      let(:uds_path) { "/var/run/datadog/apm.socket" }

      it "uses the placeholder base URL" do
        expect(adapter.base_url).to eq("http://localhost")
        expect(adapter.uds_path).to eq(uds_path)
      end
    end

    context "without an injected client" do
      let(:client) { nil }

      it "creates the native client with its configuration" do
        expect(client_class).to receive(:_native_new).with(
          base_url: "http://agent:8126", timeout_ms: 5000, unix_socket_path: nil,
        )

        adapter
      end
    end

    context "with a Unix socket and without an injected client" do
      let(:client) { nil }
      let(:uds_path) { "/tmp/a.sock" }

      it "passes the socket path with the placeholder base URL" do
        expect(client_class).to receive(:_native_new).with(
          base_url: "http://localhost", timeout_ms: 5000, unix_socket_path: "/tmp/a.sock",
        )

        adapter
      end
    end
  end

  describe ".build" do
    subject(:adapter) { described_class.build(agent_settings) }

    context "for an HTTP agent" do
      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettings.new(
          adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
          ssl: true, hostname: "agent", port: 8126, timeout_seconds: 7,
        )
      end

      it "uses the agent URL" do
        expect(client_class).to receive(:_native_new).with(
          base_url: "https://agent:8126", timeout_ms: 7000, unix_socket_path: nil,
        )

        adapter
      end
    end

    context "for a Unix socket agent" do
      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettings.new(
          adapter: Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER,
          uds_path: "/tmp/a.sock", timeout_seconds: 7,
        )
      end

      it "uses the socket" do
        expect(client_class).to receive(:_native_new).with(
          base_url: "http://localhost", timeout_ms: 7000, unix_socket_path: "/tmp/a.sock",
        )

        adapter
      end
    end
  end

  describe "#call" do
    subject(:response) { adapter.call(env) }

    it "sends the request through the native client" do
      expect(client).to receive(:_native_send).with(
        {verb: :post, path: "/v0.7/config", headers: [["X-A", "1"]], body: "payload", multipart: []},
      ).and_return(result)

      response
    end

    it "appends a Hash query to the path" do
      env.query = {"a" => "1 2", "b" => "c"}

      expect(client).to receive(:_native_send).with(hash_including(path: "/v0.7/config?a=1+2&b=c")).and_return(result)

      response
    end

    it "appends a String query to the path" do
      env.query = "a=1"

      expect(client).to receive(:_native_send).with(hash_including(path: "/v0.7/config?a=1")).and_return(result)

      response
    end

    it "rejects other query types" do
      env.query = 42

      expect { response }.to raise_error(ArgumentError, /Invalid type for query/)
    end

    context "with a multipart form" do
      let(:upload_io) { Datadog::Core::Vendor::Multipart::Post::UploadIO }

      before do
        io = StringIO.new("{}")
        io.read # consumed: the adapter must rewind it
        env.form = {
          "event" => upload_io.new(io, "application/json", "event.json"),
          "note" => "text",
        }
      end

      it "sends the parts and no body" do
        expect(client).to receive(:_native_send).with(
          hash_including(
            body: nil,
            multipart: [
              {name: "event", data: "{}", filename: "event.json", content_type: "application/json"},
              {name: "note", data: "text", filename: nil, content_type: nil},
            ],
          ),
        ).and_return(result)

        response
      end
    end

    context "when the server answers with an error status" do
      let(:result) { [:ok, 404, [["Content-Type", "text/plain"]], "nope"] }

      it "returns it as a response" do
        expect(response).to have_attributes(code: 404, payload: "nope", not_found?: true, ok?: false)
      end
    end

    context "when the native client reports an error" do
      let(:result) { [:error, :timed_out, "request timed out"] }

      it "raises an error with the code" do
        expect { response }.to raise_error(described_class::Error, /timed_out.*request timed out/) { |e|
          expect(e.code).to eq(:timed_out)
        }
      end
    end

    context "when the native client returns something unexpected" do
      let(:result) { [] }

      it "raises an error" do
        expect { response }.to raise_error(described_class::Error, /unexpected result/)
      end
    end
  end

  describe "#close" do
    it "closes the native client" do
      expect(client).to receive(:_native_close)

      adapter.close
    end

    it "closes the native client only once" do
      expect(client).to receive(:_native_close).once

      2.times { adapter.close }
    end

    it "makes later requests raise" do
      adapter.close

      expect { adapter.call(env) }.to raise_error(described_class::Error, /closed/) { |e| expect(e.code).to eq(:closed) }
    end

    it "waits for the requests in flight" do
      sending = Queue.new
      release = Queue.new
      allow(client).to receive(:_native_send) do
        sending << true
        release.pop
        result
      end
      closed = false
      allow(client).to receive(:_native_close) { closed = true }

      request = Thread.new { adapter.call(env) }
      sending.pop
      closing = Thread.new { adapter.close }

      Thread.pass until closing.status == "sleep"
      expect(closed).to be(false)

      release << true
      [request, closing].each(&:join)
      expect(closed).to be(true)
    end
  end

  describe ".unsupported_reason" do
    before { allow(described_class).to receive(:unsupported_reason).and_call_original }

    context "when the extension could not be loaded" do
      before { stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", "LoadError: boom") }

      it { expect(described_class.unsupported_reason).to match(/not available: LoadError: boom/) }
      it { expect(described_class).not_to be_supported }

      it "makes creating an adapter without a client fail" do
        expect { described_class.new(base_url: base_url, timeout: 5) }.to raise_error(/not supported.*boom/)
      end
    end

    context "when the extension was loaded without the native HTTP client" do
      before do
        stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
        hide_const("#{described_class}::Client")
      end

      it { expect(described_class.unsupported_reason).to match(/does not include the native HTTP client/) }
    end

    context "when the native HTTP client is available" do
      before { stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil) }

      it { expect(described_class.unsupported_reason).to be_nil }
      it { expect(described_class).to be_supported }
    end
  end

  describe ".register_fork_hooks" do
    let(:hooks) { {before: proc {}, parent: proc {}, child: proc {}} }

    def reset_registration
      described_class.remove_instance_variable(:@fork_hooks_registered) if described_class.instance_variable_defined?(:@fork_hooks_registered)
    end

    before do
      allow(described_class).to receive(:register_fork_hooks).and_call_original
      reset_registration
      allow(client_class).to receive_messages(
        _native_before_fork: nil, _native_after_fork_in_parent: nil, _native_after_fork_in_child: nil,
      )
      allow(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:at_fork_blocks) { |**blocks| hooks.replace(blocks) }
    end

    after { reset_registration }

    it "registers the hooks only once" do
      expect(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:at_fork_blocks).once

      expect(described_class.register_fork_hooks).to be(true)
      expect(described_class.register_fork_hooks).to be(false)
    end

    it "pauses the runtime before the fork and restarts it afterwards" do
      described_class.register_fork_hooks

      expect(client_class).to receive(:_native_before_fork).ordered
      expect(client_class).to receive(:_native_after_fork_in_parent).ordered
      expect(client_class).to receive(:_native_before_fork).ordered
      expect(client_class).to receive(:_native_after_fork_in_child).ordered

      hooks[:before].call
      hooks[:parent].call
      hooks[:before].call
      hooks[:child].call
    end

    it "keeps requests waiting between the before and after hooks" do
      described_class.register_fork_hooks
      adapter # created before the fork, with an injected client

      hooks[:before].call
      sent = false
      request = Thread.new { adapter.call(env).tap { sent = true } }
      Thread.pass until request.status == "sleep"
      expect(sent).to be(false)

      hooks[:parent].call
      request.join
      expect(sent).to be(true)
    end

    it "waits for the requests in flight before pausing the runtime" do
      described_class.register_fork_hooks
      sending = Queue.new
      release = Queue.new
      allow(client).to receive(:_native_send) do
        sending << true
        release.pop
        result
      end
      paused = false
      allow(client_class).to receive(:_native_before_fork) { paused = true }

      request = Thread.new { adapter.call(env) }
      sending.pop
      forking = Thread.new { hooks[:before].call }
      Thread.pass until forking.status == "sleep"
      expect(paused).to be(false)

      release << true
      [request, forking].each(&:join)
      expect(paused).to be(true)
      hooks[:parent].call
    end

    it "logs and carries on when the native runtime cannot be prepared" do
      described_class.register_fork_hooks
      allow(client_class).to receive(:_native_before_fork).and_raise("boom")
      expect(Datadog.logger).to receive(:warn)

      expect { hooks[:before].call }.not_to raise_error
      hooks[:parent].call
    end

    it "does not fail when the after hook has no matching before hook" do
      described_class.register_fork_hooks

      expect { hooks[:child].call }.not_to raise_error
      expect(adapter.call(env)).to be_ok
    end
  end

  describe "#url" do
    it { expect(adapter.url).to eq("http://agent:8126?timeout=5") }

    context "with a Unix socket" do
      let(:uds_path) { "/tmp/a.sock" }

      it { expect(adapter.url).to eq("http+unix:///tmp/a.sock?timeout=5") }
    end
  end

  describe described_class::Response do
    subject(:response) { described_class.new(status, [["ETag", "abc"], ["X-Y", "1"]], "body") }

    let(:status) { 200 }

    it "looks up headers case-insensitively through lowercased names" do
      expect(response.headers["etag"]).to eq("abc")
      expect(response.headers).to eq("etag" => "abc", "x-y" => "1")
    end

    {
      200 => {ok?: true, client_error?: false, server_error?: false},
      199 => {ok?: false},
      299 => {ok?: true},
      404 => {not_found?: true, client_error?: true, ok?: false, unsupported?: false},
      415 => {unsupported?: true, client_error?: true},
      500 => {server_error?: true, client_error?: false, ok?: false},
    }.each do |code, expected|
      context "with status #{code}" do
        let(:status) { code }

        it { is_expected.to have_attributes(expected) }
      end
    end

    it "is not an internal error" do
      expect(response.internal_error?).to be false
    end
  end
end
