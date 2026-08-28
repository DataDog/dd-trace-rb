# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/transport"

RSpec.describe Datadog::OpenFeature::Transport::HTTP do
  subject(:transport) { described_class.build(agent_settings: test_agent_settings, logger: logger) }
  let(:logger) { logger_allowing_debug }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.disable!
  end

  describe "#send_exposures" do
    before { stub_request(:post, %r{/evp_proxy/v2/api/v2/exposures}).to_return(status: 201, body: "") }

    context "when request was successful" do
      it "posts encoded payload to exposures endpoint" do
        transport.send_exposures("event" => "value")

        expect(
          a_request(:post, %r{/evp_proxy/v2/api/v2/exposures})
            .with(
              headers: {"X-Datadog-EVP-Subdomain" => "event-platform-intake"},
              body: '{"event":"value"}'
            )
        ).to have_been_made.once
      end
    end

    context "when exception was raised during request" do
      before { stub_request(:post, %r{/evp_proxy/v2/api/v2/exposures}).to_raise(Timeout::Error.new("Ooops")) }

      it "returns internal error response and logs debug message" do
        expect(logger).to receive(:debug).with(/Internal error during request\. Cause: Timeout::Error: Ooops/)

        expect(transport.send_exposures("event" => "value")).to be_a(Datadog::Core::Transport::InternalErrorResponse)
      end
    end
  end

  describe "#send_flag_evaluations" do
    subject(:transport) { described_class.build_flagevaluations(agent_settings: test_agent_settings, logger: logger) }

    before { stub_request(:post, %r{/evp_proxy/v2/api/v2/flagevaluation}).to_return(status: 201, body: "") }

    context "when request was successful" do
      it "posts encoded payload and SDK identity to flagevaluation endpoint" do
        response = transport.send_flag_evaluations("event" => "value")

        expect(response.code).to eq(201)
        expect(
          a_request(:post, %r{/evp_proxy/v2/api/v2/flagevaluation})
            .with(
              headers: {
                "Content-Type" => "application/json",
                "DD-EVP-ORIGIN" => "dd-trace-rb",
                "DD-EVP-ORIGIN-VERSION" => Datadog::VERSION::STRING,
                "X-Datadog-EVP-Subdomain" => "event-platform-intake",
              },
              body: '{"event":"value"}'
            )
        ).to have_been_made.once
      end
    end

    context "when exception was raised during request" do
      before do
        stub_request(:post, %r{/evp_proxy/v2/api/v2/flagevaluation}).to_raise(Timeout::Error.new("Ooops"))
      end

      it "returns internal error response and logs debug message" do
        expect(logger).to receive(:debug).with(/Internal error during request\. Cause: Timeout::Error: Ooops/)

        response = transport.send_flag_evaluations("event" => "value")

        expect(response).to be_a(Datadog::Core::Transport::InternalErrorResponse)
      end
    end
  end
end
