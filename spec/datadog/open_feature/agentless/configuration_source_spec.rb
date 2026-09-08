# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "zlib"
require "datadog/open_feature/configuration/agentless_endpoint"
require "datadog/open_feature/agentless/configuration_source"

RSpec.describe Datadog::OpenFeature::Agentless::ConfigurationSource do
  subject(:source) do
    described_class.new(
      endpoint: endpoint,
      api_key: "secret",
      poll_interval_seconds: 30,
      request_timeout_seconds: 5,
      apply: apply,
      logger: logger,
      transport: transport,
      random: -> { 0.5 },
      retry_wait: retry_wait,
    )
  end

  let(:endpoint) do
    Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
      URI("https://example.test/config"),
      managed: true,
    )
  end
  let(:transport) { instance_double(Datadog::OpenFeature::Agentless::Transport) }
  let(:logger) { instance_double(Datadog::Core::Logger, warn: nil, error: nil) }
  let(:apply) { ->(_configuration) {} }
  let(:retry_wait) { ->(_delay) { false } }
  let(:attributes) do
    {
      "format" => "SERVER",
      "createdAt" => "2026-09-08T00:00:00Z",
      "environment" => {"name" => "test"},
      "flags" => {},
    }
  end
  let(:body) do
    JSON.generate(
      "data" => {
        "type" => "universal-flag-configuration",
        "attributes" => attributes,
      },
    )
  end

  def response(status:, etag: nil, body: nil, error: nil)
    Datadog::OpenFeature::Agentless::Response.new(
      status: status,
      etag: etag,
      body: body,
      error: error,
    )
  end

  describe ".build" do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    before { settings.api_key = nil }

    it "rejects a managed endpoint without an API key" do
      expect(logger).to receive(:warn).with(a_string_including("requires DD_API_KEY"))

      expect(described_class.build(settings, endpoint: endpoint, apply: apply, logger: logger)).to be_nil
    end

    context "with a custom endpoint" do
      let(:endpoint) do
        Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
          URI("https://example.test/config"),
          managed: false,
        )
      end

      it "does not require an API key" do
        expect(described_class.build(settings, endpoint: endpoint, apply: apply, logger: logger))
          .to be_a(described_class)
      end
    end
  end

  describe "#poll" do
    it "applies a 200 response and advances the ETag" do
      expect(transport).to receive(:get).with(nil).and_return(response(status: 200, etag: " next ", body: body))
      expect(apply).to receive(:call).with(JSON.generate(attributes))

      expect { source.poll }.to change(source, :etag).from(nil).to("next")
    end

    it "sends the accepted ETag on the next poll" do
      allow(transport).to receive(:get).with(nil).and_return(response(status: 200, etag: "first", body: body))
      source.poll
      expect(transport).to receive(:get).with("first").and_return(response(status: 304))

      source.poll
    end

    it "does not apply a 304 response" do
      expect(transport).to receive(:get).with(nil).and_return(response(status: 304))
      expect(apply).not_to receive(:call)

      source.poll
    end

    it "retries transport errors three times" do
      error_response = response(status: nil, error: Net::ReadTimeout.new)
      expect(transport).to receive(:get).with(nil).exactly(3).times.and_return(error_response)
      expect(logger).to receive(:warn).once.with(a_string_including("after 3 attempt(s): Net::ReadTimeout"))

      source.poll
    end

    context "when retrying" do
      let(:retry_delays) { [] }
      let(:retry_wait) do
        lambda do |delay|
          retry_delays << delay
          false
        end
      end

      it "uses interval-derived backoff between attempts" do
        allow(transport).to receive(:get).and_return(response(status: 500))

        source.poll

        expect(retry_delays).to eq([5.0, 10.0])
      end
    end

    [408, 429, 500, 599].each do |status|
      it "retries HTTP #{status} three times" do
        status_response = response(status: status)
        expect(transport).to receive(:get).with(nil).exactly(3).times.and_return(status_response)

        source.poll
      end
    end

    it "does not retry a non-retryable status" do
      expect(transport).to receive(:get).with(nil).once.and_return(response(status: 400))

      source.poll
    end

    it "reports an authentication failure without retrying" do
      expect(transport).to receive(:get).with(nil).once.and_return(response(status: 401))
      expect(logger).to receive(:warn).once.with(a_string_including("verify endpoint authentication"))

      source.poll
    end

    it "keeps the ETag when the next payload is malformed" do
      allow(transport).to receive(:get).with(nil).and_return(response(status: 200, etag: "good", body: body))
      source.poll
      allow(transport).to receive(:get).with("good").and_return(response(status: 200, etag: "bad", body: "{"))

      expect { 2.times { source.poll } }.not_to change(source, :etag).from("good")
      expect(logger).to have_received(:error).once.with(a_string_including("malformed UFC payload"))
    end

    it "keeps the ETag when configuration cannot be applied" do
      expect(transport).to receive(:get).with(nil).and_return(response(status: 200, etag: "rejected", body: body))
      allow(apply).to receive(:call).and_raise(Datadog::OpenFeature::EvaluationEngine::ReconfigurationError)

      expect { source.poll }.not_to change(source, :etag).from(nil)
    end
  end

  describe "lifecycle" do
    let(:retry_wait) { nil }

    it "performs no request before start and starts asynchronously once" do
      requested = SizedQueue.new(1)
      allow(transport).to receive(:get) do
        requested.push(true, true)
        response(status: 304)
      rescue ThreadError
        response(status: 304)
      end

      expect(transport).not_to have_received(:get)
      expect(source.start).to be(true)
      expect(source.start).to be(true)
      Timeout.timeout(1) { requested.pop }
      expect(source.stop).to be(true)
      expect(transport).to have_received(:get).once
    ensure
      source&.stop
    end

    it "cannot start after it has stopped" do
      allow(transport).to receive(:get)
      expect(source.stop).to be(true)

      expect(source.start).to be(false)
      expect(transport).not_to have_received(:get)
    end
  end
end
