require "datadog/tracing/contrib/support/spec_helper"

require "datadog"
require "net/http"

RSpec.describe Datadog::Tracing::Contrib::HTTP::Instrumentation do
  after do
    WebMock.reset!
    WebMock.disable!
  end

  let(:host) { "127.0.0.1" }
  let(:port) { 1234 }
  let(:uri) { "http://#{host}:#{port}" }
  let(:path) { "/my/path" }

  let(:client) { Net::HTTP.new(host, port) }
  let(:configuration_options) { {} }

  before do
    WebMock.enable!(allow: agent_url)
    Datadog.configure { |c| c.tracing.instrument :http, configuration_options }
    stub_request(:get, "#{uri}#{path}").to_return(status: 200, body: "{}")
  end

  around do |example|
    Datadog.registry[:http].reset_configuration!
    example.run
    Datadog.registry[:http].reset_configuration!
  end

  describe "#request" do
    subject(:response) { client.get(path) }

    shared_examples "does not build or trace a span" do
      it "does not build or trace a span" do
        expect(Datadog::Tracing::SpanOperation).not_to receive(:new)
        expect(Datadog::Tracing).not_to receive(:trace)

        is_expected.to be_a(Net::HTTPResponse)
        expect(response.code).to eq("200")
        expect(spans).to be_empty
      end
    end

    context "when tracing is disabled" do
      before do
        Datadog.configure { |c| c.tracing.enabled = false }
      end

      include_examples "does not build or trace a span"
    end

    context "when the http integration is disabled after patching" do
      before do
        Datadog.configure { |c| c.tracing.instrument :http, enabled: false }
      end

      include_examples "does not build or trace a span"
    end

    context "when the http integration is disabled after patching and the host has a describes override" do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :http, describes: /127\.0\.0\.1/, service_name: "override-service"
          c.tracing.instrument :http, enabled: false
        end
      end

      include_examples "does not build or trace a span"
    end

    context "when the http integration is re-enabled after being disabled" do
      before do
        Datadog.configure { |c| c.tracing.instrument :http, enabled: false }
        Datadog.configure { |c| c.tracing.instrument :http, enabled: true }
      end

      it "traces the request" do
        expect(response.code).to eq("200")
        expect(spans).to have(1).item
        expect(spans.first.name).to eq("http.request")
      end
    end
  end
end
