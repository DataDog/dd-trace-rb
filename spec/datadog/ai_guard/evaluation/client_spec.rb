# frozen_string_literal: true

require "datadog/ai_guard/component"

RSpec.describe Datadog::AIGuard::Evaluation::Client do
  describe ".evaluate" do
    subject(:outcome) { described_class.evaluate(messages) }

    before do
      allow(Datadog::AIGuard).to receive(:http_client).and_return(http_client)
      allow(Datadog.configuration.ai_guard).to receive(:redaction_enabled).and_return(true)
      allow(http_client).to receive(:post).and_return(raw_response)
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

    context "when the HTTP client is initialized" do
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
    end

    context "when redaction is enabled and the response has no replacements" do
      it "returns the original typed messages with a performed redaction result" do
        aggregate_failures "evaluation without replacements" do
          expect(outcome.result.messages).to equal(messages)
          expect(outcome.result.messages).to all(be_a(Datadog::AIGuard::Evaluation::Message))
          expect(outcome.redaction).to be_performed
          expect(outcome.redaction).not_to be_redacted
        end
      end
    end

    context "when redaction is enabled and the response has replacements" do
      let(:raw_response) do
        {
          "data" => {
            "attributes" => {
              "action" => "ALLOW",
              "reason" => "Sensitive data detected",
              "tags" => ["sensitive-data"],
              "sds_findings" => [
                {
                  "rule_tag" => "us_ssn",
                  "location" => {"path" => "messages[0].content"},
                },
              ],
              "tag_probs" => {"sensitive-data" => 0.8},
              "is_blocking_enabled" => false,
              "redaction_replacements" => [
                {
                  "path" => "messages[0].content",
                  "replacement" => "Hello <REDACTED>",
                },
              ],
            },
          },
        }
      end

      it "returns redacted typed messages through the result and outcome" do
        aggregate_failures "redacted evaluation outcome" do
          expect(outcome.result.messages).to all(be_a(Datadog::AIGuard::Evaluation::Message))
          expect(outcome.result.messages.map(&:to_h)).to eq([
            {role: :user, content: "Hello <REDACTED>"},
          ])
          expect(outcome.redaction).to be_a(Datadog::AIGuard::Redaction::Result)
          expect(outcome.redaction.messages).to equal(outcome.result.messages)
          expect(outcome.redaction).to be_performed
          expect(outcome.redaction).to be_redacted
        end
      end

      it "preserves response metadata on the evaluation result" do
        aggregate_failures "evaluation response metadata" do
          expect(outcome.result.action).to eq("ALLOW")
          expect(outcome.result.reason).to eq("Sensitive data detected")
          expect(outcome.result.tags).to eq(["sensitive-data"])
          expect(outcome.result.sds_findings).to eq([
            {
              "rule_tag" => "us_ssn",
              "location" => {"path" => "messages[0].content"},
            },
          ])
          expect(outcome.result.tag_probabilities).to eq("sensitive-data" => 0.8)
        end
      end
    end

    context "when redaction is disabled and the response has replacements" do
      before { allow(Datadog.configuration.ai_guard).to receive(:redaction_enabled).and_return(false) }

      let(:raw_response) do
        {
          "data" => {
            "attributes" => {
              "action" => "ALLOW",
              "reason" => "Sensitive data detected",
              "tags" => [],
              "sds_findings" => [
                {
                  "rule_tag" => "us_ssn",
                  "location" => {"path" => "messages[0].content"},
                },
              ],
              "tag_probs" => {},
              "is_blocking_enabled" => false,
              "redaction_replacements" => [
                {
                  "path" => "messages[0].content",
                  "replacement" => "Hello <REDACTED>",
                },
              ],
            },
          },
        }
      end

      it "returns the original messages and marks redaction as skipped" do
        aggregate_failures "locally disabled redaction" do
          expect(outcome.result.messages).to equal(messages)
          expect(outcome.result.messages.map(&:to_h)).to eq([
            {role: :user, content: "Hello there"},
          ])
          expect(outcome.redaction.messages).to equal(messages)
          expect(outcome.redaction).not_to be_performed
          expect(outcome.redaction).not_to be_redacted
        end
      end
    end

    context "when the HTTP client is not initialized" do
      before { allow(Datadog::AIGuard).to receive(:http_client).and_return(nil) }

      it "raises an error" do
        expect { outcome }.to raise_error(RuntimeError, "AI Guard HTTP client not initialized")
      end
    end
  end
end
