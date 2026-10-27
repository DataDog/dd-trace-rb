# frozen_string_literal: true

require "spec_helper"
require "timeout"
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
      random: random,
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
  let(:logger) { instance_double(Datadog::Core::Logger, warn: nil, error: nil, debug: nil, debug?: true) }
  let(:apply) { ->(_configuration) {} }
  let(:random) { -> { 0.5 } }
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

      context "at the bottom of the random range" do
        let(:random) { -> { 0.0 } }

        it "subtracts the full jitter from the backoff" do
          allow(transport).to receive(:get).and_return(response(status: 500))

          source.poll

          expect(retry_delays).to eq([4.0, 8.0])
        end
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

    {
      401 => "configuration request lacks valid authentication credentials",
      403 => "access to the configuration endpoint is forbidden",
    }.each do |status, reason|
      it "reports HTTP #{status} as an authentication failure without retrying" do
        expect(transport).to receive(:get).with(nil).once.and_return(response(status: status))
        expect(logger).to receive(:warn).once.with(
          "Feature Flags agentless #{reason}; verify endpoint authentication (HTTP #{status})"
        )

        source.poll
      end
    end

    it "reports an unexpected status after a retryable status has warned" do
      allow(transport).to receive(:get).and_return(response(status: 500))
      source.poll

      allow(transport).to receive(:get).and_return(response(status: 404))
      source.poll

      expect(logger).to have_received(:warn)
        .with("Feature Flags agentless configuration endpoint encountered an internal error after 3 attempt(s) (HTTP 500); next poll in 30s").once
      expect(logger).to have_received(:warn)
        .with("Feature Flags agentless configuration endpoint not found after 1 attempt(s) (HTTP 404)").once
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

    it "retries through each response outcome with debug logging enabled" do
      allow(logger).to receive(:debug) { |message, &block| block ? block.call : message }
      allow(transport).to receive(:get).and_return(
        response(status: nil, error: SocketError.new),
        response(status: 503),
        response(status: 304),
      )

      source.poll

      expect(transport).to have_received(:get).exactly(3).times
      expect(logger).not_to have_received(:error)
    end

    context "with debug logging enabled" do
      let(:debug_messages) { [] }

      before { allow(logger).to receive(:debug) { |message, &block| debug_messages << (block ? block.call : message) } }

      [
        [400, "configuration request rejected as invalid", 1],
        [404, "configuration endpoint not found", 1],
        [408, "configuration request timed out", 3],
        [429, "configuration request rate limited", 3],
        [500, "configuration endpoint encountered an internal error", 3],
        [502, "configuration endpoint received an invalid upstream response", 3],
        [503, "configuration endpoint is temporarily unavailable", 3],
        [504, "configuration endpoint timed out waiting for an upstream response", 3],
        [599, "configuration endpoint reported a server error", 3],
        [302, "unexpected response from the configuration endpoint", 1],
        [499, "unexpected response from the configuration endpoint", 1],
      ].each do |status, reason, attempts|
        it "explains HTTP #{status} in poll diagnostics and the failure warning" do
          allow(transport).to receive(:get).and_return(response(status: status))

          source.poll

          expect(debug_messages.grep(/poll attempt/)).to eq(
            (1..attempts).map do |attempt|
              "Feature Flags: agentless configuration poll attempt #{attempt}/3: #{reason} (HTTP #{status})"
            end
          )
          refresh = (attempts == 3) ? "; next poll in 30s" : ""
          expect(logger).to have_received(:warn).once.with(
            "Feature Flags agentless #{reason} after #{attempts} attempt(s) (HTTP #{status})#{refresh}"
          )
        end
      end

      it "logs the ETag of a received configuration" do
        allow(transport).to receive(:get).and_return(response(status: 200, etag: '"v42"', body: body))

        source.poll

        expect(debug_messages).to eq(['Feature Flags: agentless configuration poll attempt 1/3: configuration received (ETag "v42"; HTTP 200)'])
      end

      it "logs a received configuration without an ETag" do
        allow(transport).to receive(:get).and_return(response(status: 200, body: body))

        source.poll

        expect(debug_messages).to eq(["Feature Flags: agentless configuration poll attempt 1/3: configuration received (HTTP 200)"])
      end

      it "logs when the configuration is unchanged" do
        allow(transport).to receive(:get).and_return(response(status: 304))

        source.poll

        expect(debug_messages).to eq(["Feature Flags: agentless configuration poll attempt 1/3: configuration unchanged (HTTP 304)"])
      end

      it "logs when the configuration could not be retrieved" do
        allow(transport).to receive(:get).and_return(response(status: 404))

        source.poll

        expect(debug_messages).to eq(["Feature Flags: agentless configuration poll attempt 1/3: configuration endpoint not found (HTTP 404)"])
      end

      it "logs every ignored malformed payload" do
        allow(transport).to receive(:get).and_return(response(status: 200, body: "{"))

        2.times { source.poll }

        expect(debug_messages.grep(/ignoring malformed/)).to eq(
          ["Feature Flags: ignoring malformed agentless configuration payload"] * 2
        )
      end

      it "logs when polling stops" do
        source.stop

        expect(debug_messages).to eq(["Feature Flags: stopped agentless configuration polling"])
      end

      it "logs repeated terminal failures at debug after the first warning" do
        allow(transport).to receive(:get).and_return(response(status: 500))
        message = "Feature Flags agentless configuration endpoint encountered an internal error after 3 attempt(s) (HTTP 500); next poll in 30s"

        2.times { source.poll }

        expect(logger).to have_received(:warn).with(message).once
        expect(debug_messages.count(message)).to eq(1)
      end

      it "logs recovery once after failed polls" do
        allow(transport).to receive(:get).and_return(
          response(status: 404),
          response(status: 401),
          response(status: 304),
          response(status: 304),
        )

        4.times { source.poll }

        expect(debug_messages.grep(/recovered/)).to eq(
          ["Feature Flags: agentless configuration delivery recovered after 2 failed poll(s)"]
        )
      end
    end
  end

  describe "#perform" do
    it "continues polling after an unexpected error" do
      request_count = 0
      perform_iteration = source.method(:perform)
      until perform_iteration.owner == described_class
        wrapped_method = perform_iteration.super_method
        raise "ConfigurationSource#perform is missing" unless wrapped_method

        perform_iteration = wrapped_method
      end
      allow(transport).to receive(:get) do
        request_count += 1
        raise TypeError unless request_count == 2

        response(status: 304)
      end

      expect { 3.times { perform_iteration.call } }.not_to raise_error
      expect(request_count).to eq(3)
      expect(logger).to have_received(:error).once.with(
        "Feature Flags agentless poll failed with TypeError; polling continues",
      )
    end
  end

  describe "#after_fork" do
    it "allows the child process to report a failure already reported by the parent" do
      allow(transport).to receive(:get).and_return(response(status: 404))

      2.times { source.poll }
      expect(logger).to have_received(:warn)
        .with("Feature Flags agentless configuration endpoint not found after 1 attempt(s) (HTTP 404)").once

      source.send(:after_fork)
      source.poll

      expect(logger).to have_received(:warn)
        .with("Feature Flags agentless configuration endpoint not found after 1 attempt(s) (HTTP 404)").twice
    end
  end

  describe "lifecycle" do
    let(:retry_wait) { nil }

    it "performs no request before start" do
      allow(transport).to receive(:get)

      expect(source).to be_a(described_class)
      expect(transport).not_to have_received(:get)
    end

    it "starts asynchronously once" do
      requested = SizedQueue.new(1)
      allow(transport).to receive(:get) do
        requested.push(true, true)
        response(status: 304)
      rescue ThreadError
        response(status: 304)
      end

      expect(source.start).to be(true)
      expect(source.start).to be(true)
      Timeout.timeout(1) { requested.pop }
      expect(source.stop(false, 1)).to be(true)
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
