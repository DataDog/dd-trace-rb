# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/appsec/spec_helper"

require "datadog/tracing"
require "datadog/appsec"

RSpec.describe "AWS Lambda blocking" do
  before do
    Datadog.configure do |c|
      c.tracing.enabled = true

      c.appsec.enabled = true
      c.appsec.instrument :aws_lambda
      c.appsec.ruleset = {
        rules: [
          {
            id: "test-blocking-user-agent",
            name: "Block test scanner",
            tags: {type: "security_scanner", category: "attack_attempt"},
            conditions: [
              {
                parameters: {
                  inputs: [{address: "server.request.headers.no_cookies", key_path: ["user-agent"]}],
                  regex: "^dd-test-scanner-block$",
                },
                operator: "match_regex",
              },
            ],
            transformers: [],
            on_match: ["block"],
          },
          {
            id: "test-blocking-response-status",
            name: "Block teapot response",
            tags: {type: "security_scanner", category: "attack_attempt"},
            conditions: [
              {
                parameters: {
                  inputs: [{address: "server.response.status"}],
                  regex: "^418$",
                },
                operator: "match_regex",
              },
            ],
            transformers: [],
            on_match: ["block"],
          },
        ],
      }

      c.remote.enabled = false
    end

    allow_any_instance_of(Datadog::Tracing::Transport::HTTP::Client).to receive(:send_request)
  end

  after { Datadog.configuration.reset! }

  # NOTE: Emulates datadog-lambda-rb, which activates the context and catches the interrupt
  def push_and_catch(event_name, data)
    Datadog::Tracing.trace("aws.lambda") do |span, trace|
      context = Datadog::AppSec::Context.new(trace, span, Datadog::AppSec.security_engine.new_runner)
      Datadog::AppSec::Context.activate(context)

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        Datadog::AppSec::Instrumentation.gateway.push(
          event_name, Datadog::AppSec::Instrumentation::Gateway::DataContainer.new(data, context: context),
        )
        nil
      end
    ensure
      Datadog::AppSec::Context.deactivate
    end
  end

  context "when request matches a blocking rule" do
    let(:interrupt_params) do
      push_and_catch(
        "aws_lambda.request.start",
        {"method" => "GET", "path" => "/", "headers" => {"User-Agent" => "dd-test-scanner-block"}},
      )
    end

    it { expect(interrupt_params).to include("status_code" => 403) }
  end

  context "when request does not match a blocking rule" do
    let(:interrupt_params) do
      push_and_catch(
        "aws_lambda.request.start",
        {"method" => "GET", "path" => "/", "headers" => {"User-Agent" => "Mozilla/5.0"}},
      )
    end

    it { expect(interrupt_params).to be_nil }
  end

  context "when response matches a blocking rule" do
    let(:interrupt_params) do
      push_and_catch("aws_lambda.response.start", {"status_code" => 418, "headers" => {}})
    end

    it { expect(interrupt_params).to include("status_code" => 403) }
  end

  context "when response does not match a blocking rule" do
    let(:interrupt_params) do
      push_and_catch("aws_lambda.response.start", {"status_code" => 200, "headers" => {}})
    end

    it { expect(interrupt_params).to be_nil }
  end
end
