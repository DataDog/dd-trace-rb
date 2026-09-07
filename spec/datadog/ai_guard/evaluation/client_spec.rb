# frozen_string_literal: true

require "datadog/ai_guard/component"

RSpec.describe Datadog::AIGuard::Evaluation::Client do
  describe ".evaluate" do
    subject(:outcome) { described_class.evaluate(messages) }

    before do
      allow(Datadog::AIGuard).to receive(:http_client).and_return(http_client)
      allow(Datadog.configuration.ai_guard).to receive(:redaction_enabled).and_return(true)
    end

    let(:http_client) { instance_double(Datadog::AIGuard::HTTPClient) }
    let(:messages) do
      [
        Datadog::AIGuard::Evaluation::Message.new(role: :user, content: "Hello there"),
      ]
    end
    let(:raw_response) do
      {
        "data" => {
          "attributes" => {
            "action" => "ALLOW",
            "reason" => "Because why not",
            "tags" => [],
            "tag_probs" => {},
            "is_blocking_enabled" => false,
          },
        },
      }
    end

    it "sends the evaluation request through the HTTP client" do
      expect(http_client).to receive(:post).with(
        "/evaluate",
        body: {
          data: {
            attributes: {
              messages: [
                {content: "Hello there", role: :user},
              ],
              meta: {
                service: Datadog.configuration.service,
                env: Datadog.configuration.env,
              },
            },
          },
        }
      ).and_return(raw_response)

      expect(outcome.result).to be_a(Datadog::AIGuard::Evaluation::Result)
    end

    context "when the HTTP client is not initialized" do
      before { allow(Datadog::AIGuard).to receive(:http_client).and_return(nil) }

      it "raises an error" do
        expect { outcome }.to raise_error(RuntimeError, "AI Guard HTTP client not initialized")
      end
    end
  end
end
