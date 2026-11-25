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
  let(:client) { instance_double(described_class::Client, _native_send: result, _native_close: nil) }
  let(:result) { [:ok, 200, [], ""] }

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
        expect(described_class::Client).to receive(:_native_new).with(
          base_url: "http://agent:8126", timeout_ms: 5000, unix_socket_path: nil,
        )

        adapter
      end
    end

    context "with a Unix socket and without an injected client" do
      let(:client) { nil }
      let(:uds_path) { "/tmp/a.sock" }

      it "passes the socket path with the placeholder base URL" do
        expect(described_class::Client).to receive(:_native_new).with(
          base_url: "http://localhost", timeout_ms: 5000, unix_socket_path: "/tmp/a.sock",
        )

        adapter
      end
    end
  end

  describe ".build" do
    subject(:adapter) { described_class.build(agent_settings) }

    before { allow(described_class::Client).to receive(:_native_new).and_return(client) }

    context "for an HTTP agent" do
      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettings.new(
          adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
          ssl: true, hostname: "agent", port: 8126, timeout_seconds: 7,
        )
      end

      it "uses the agent URL" do
        expect(described_class::Client).to receive(:_native_new).with(
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
        expect(described_class::Client).to receive(:_native_new).with(
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
        verb: :post, path: "/v0.7/config", headers: [["X-A", "1"]], body: "payload", multipart: [],
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
