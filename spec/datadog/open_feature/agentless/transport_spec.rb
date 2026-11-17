# frozen_string_literal: true

require "spec_helper"
require "socket"
require "datadog/open_feature/configuration/agentless_endpoint"
require "datadog/open_feature/agentless/transport"

RSpec.describe Datadog::OpenFeature::Agentless::Transport do
  subject(:response) { transport.get(etag) }

  let(:transport) do
    described_class.new(endpoint: endpoint, api_key: "secret", timeout_seconds: 5)
  end
  let(:endpoint) do
    Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
      URI("https://example.test/config?dd_env=test"),
      managed: managed,
    )
  end
  let(:managed) { true }
  let(:etag) { "previous" }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.disable!
  end

  before do
    stub_request(:get, "https://example.test/config?dd_env=test")
      .to_return(status: 200, body: "configuration", headers: {"ETag" => "next"})
  end

  it "sends configuration headers and returns the response" do
    expect(response.status).to eq(200)
    expect(response.etag).to eq("next")
    expect(response.body).to eq("configuration")
    expect(
      a_request(:get, "https://example.test/config?dd_env=test").with(
        headers: {
          "Accept-Encoding" => "gzip",
          "DD-API-KEY" => "secret",
          "DD-Client-Library-Language" => "ruby",
          "DD-Client-Library-Version" => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
          "DD-Internal-Untraced-Request" => "1",
          "If-None-Match" => "previous",
        },
      ),
    ).to have_been_made.once
  end

  context "with a custom endpoint" do
    let(:managed) { false }

    it "does not send the API key" do
      response

      expect(
        a_request(:get, "https://example.test/config?dd_env=test").with do |request|
          !request.headers.key?("Dd-Api-Key")
        end,
      ).to have_been_made.once
    end

    context "with URL credentials" do
      let(:endpoint) do
        Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
          URI("https://user:password@example.test/custom/path"),
          managed: false,
        )
      end

      before do
        stub_request(:get, "https://example.test/custom/path")
          .with(basic_auth: ["user", "password"])
          .to_return(status: 200, body: "configuration")
      end

      it "uses Basic authentication" do
        expect(response.status).to eq(200)
        expect(
          a_request(:get, "https://example.test/custom/path")
            .with(basic_auth: ["user", "password"]),
        ).to have_been_made.once
      end
    end

    context "with an IPv6 literal" do
      let(:endpoint) do
        Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
          URI("http://[::1]:8126/config"),
          managed: false,
        )
      end

      before do
        stub_request(:get, "http://[::1]:8126/config")
          .to_return(status: 200, body: "configuration")
      end

      it "connects using the hostname without brackets" do
        expect(Net::HTTP).to receive(:new).with("::1", 8126).and_call_original

        expect(response.status).to eq(200)
      end
    end
  end

  context "when the request fails" do
    before do
      stub_request(:get, "https://example.test/config?dd_env=test").to_raise(Net::ReadTimeout)
    end

    it "returns the transport error" do
      expect(response.status).to be_nil
      expect(response.error).to be_a(Net::ReadTimeout)
    end
  end

  context "when the connection closes before responding" do
    let(:server) { TCPServer.new("127.0.0.1", 0) }
    let(:endpoint) do
      Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
        URI("http://127.0.0.1:#{server.addr[1]}/config"),
        managed: false,
      )
    end

    around do |example|
      WebMock.disable!
      example.run
    ensure
      WebMock.enable!
    end

    it "does not retry inside the transport" do
      accepted_connections = SizedQueue.new(2)
      server_thread = Thread.new do
        loop do
          connection = server.accept
          begin
            accepted_connections.push(true)
          ensure
            connection.close
          end
        end
      rescue IOError, Errno::EBADF
        nil
      end

      begin
        expect(response.error).not_to be_nil
      ensure
        server.close
        server_thread.join(1)
      end

      expect(accepted_connections.size).to eq(1)
    end
  end

  it "uses proxy discovery and applies the request timeout" do
    expect(Net::HTTP).to receive(:new).with("example.test", 443).and_wrap_original do |original, *arguments|
      http = original.call(*arguments)
      expect(http).to receive(:open_timeout=).with(5).and_call_original
      expect(http).to receive(:read_timeout=).with(5).and_call_original
      expect(http).to receive(:write_timeout=).with(5).and_call_original
      http
    end
    expect(Timeout).to receive(:timeout).with(5).and_call_original

    response
  end

  context "with a gzip response" do
    before do
      compressed = StringIO.new
      Zlib::GzipWriter.wrap(compressed) { |writer| writer.write("configuration") }
      stub_request(:get, "https://example.test/config?dd_env=test")
        .to_return(status: 200, body: compressed.string, headers: {"Content-Encoding" => "gzip"})
    end

    it "decompresses the response body" do
      expect(response.body).to eq("configuration")
    end
  end

  describe "DD-Flag-Selection-Ignored" do
    let(:endpoint) do
      Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
        URI("https://example.test/config?dd_env=test"),
        managed: true,
        flag_selection_sent: flag_selection_sent,
      )
    end
    let(:flag_selection_sent) { true }
    let(:status) { 200 }

    before do
      stub_request(:get, "https://example.test/config?dd_env=test")
        .to_return(status: status, body: "configuration", headers: {"DD-Flag-Selection-Ignored" => "invalid_tag"})
    end

    it "is read from a 200 response to a request with a selection" do
      expect(response.flag_selection_ignored).to eq("invalid_tag")
    end

    context "without a selection in the request" do
      let(:flag_selection_sent) { false }

      it "is not read" do
        expect(response.status).to eq(200)
        expect(response.flag_selection_ignored).to be_nil
      end
    end

    [304, 400, 500].each do |non_success_status|
      context "on an HTTP #{non_success_status} response" do
        let(:status) { non_success_status }

        it "is not read" do
          expect(response.status).to eq(non_success_status)
          expect(response.flag_selection_ignored).to be_nil
        end
      end
    end
  end

  [304, 401].each do |status|
    context "with a gzip header on an HTTP #{status} response" do
      before do
        stub_request(:get, "https://example.test/config?dd_env=test")
          .to_return(status: status, body: "not gzip", headers: {"Content-Encoding" => "gzip"})
      end

      it "preserves the status without decoding the response body" do
        expect(response.status).to eq(status)
        expect(response.body).to be_nil
        expect(response.error).to be_nil
      end
    end
  end
end
