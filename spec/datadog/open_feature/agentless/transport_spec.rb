# frozen_string_literal: true

require "spec_helper"
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
      )
    ).to have_been_made.once
  end

  context "with a custom endpoint" do
    let(:managed) { false }

    it "does not send the API key" do
      response

      expect(
        a_request(:get, "https://example.test/config?dd_env=test").with do |request|
          !request.headers.key?("Dd-Api-Key")
        end
      ).to have_been_made.once
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
end
