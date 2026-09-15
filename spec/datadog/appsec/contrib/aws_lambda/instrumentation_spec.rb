# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/aws_lambda/instrumentation"

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Instrumentation do
  let(:gateway) { instance_double(Datadog::AppSec::Instrumentation::Gateway) }
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
  let(:security_engine) { double("security engine", new_runner: runner) }
  let(:runner) { double("WAF runner") }
  let(:state) { {} }
  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      state: state,
      trace: trace,
      span: span,
      interrupted?: false,
      mark_as_interrupted!: nil,
      extract_schema!: nil,
      export_metrics: nil,
      export_request_telemetry: nil,
    )
  end
  let(:event) do
    {
      "httpMethod" => "GET",
      "path" => "/users",
      "headers" => {"Host" => "example.com"},
      "requestContext" => {"identity" => {"sourceIp" => "192.0.2.1"}},
    }
  end

  before do
    allow(Datadog::AppSec).to receive_messages(enabled?: true, security_engine: security_engine)
    allow(Datadog::AppSec::Context).to receive_messages(new: context, activate: nil, active: context, deactivate: nil)
    allow(Datadog::AppSec::Instrumentation).to receive(:gateway).and_return(gateway)
    allow(gateway).to receive(:push)
    allow(Datadog::AppSec::Contrib::AwsLambda::Tagging).to receive_messages(
      tag_and_keep: nil,
      tag_request: nil,
      tag_response: nil,
    )
    allow(Datadog::AppSec::APISecurity).to receive(:enabled?).and_return(false)
    allow(Datadog::AppSec::Event).to receive(:record)
  end

  describe ".on_start" do
    it "creates a request-bound context and sends the normalized event through the gateway" do
      described_class.on_start(event, trace: trace, span: span, cold_start: true)

      request = state[:aws_lambda_request]
      expect(request).to be_a(Datadog::AppSec::Contrib::AwsLambda::Request)
      expect(request.remote_addr).to eq("192.0.2.1")
      expect(gateway).to have_received(:push) do |name, payload|
        expect(name).to eq("aws_lambda.request.start")
        expect(payload.data).to include("method" => "GET", "path" => "/users")
        expect(payload.context).to be(context)
      end
    end

    it "does nothing when AppSec is disabled" do
      allow(Datadog::AppSec).to receive(:enabled?).and_return(false)

      expect(described_class.on_start(event, trace: trace, span: span)).to be_nil
      expect(gateway).not_to have_received(:push)
    end

    it "returns an API Gateway response when request inspection blocks" do
      allow(gateway).to receive(:push) do
        throw(Datadog::AppSec::Ext::INTERRUPT, "status_code" => 403, "type" => "json")
      end

      response = described_class.on_start(event, trace: trace, span: span)

      expect(response).to include("statusCode" => 403)
      expect(response["headers"]).to include("Content-Type" => "application/json")
      expect(context).to have_received(:mark_as_interrupted!)
    end
  end

  describe ".on_finish" do
    before do
      described_class.on_start(event, trace: trace, span: span)
      allow(gateway).to receive(:push)
    end

    it "inspects the response, records events, exports metrics, and deactivates the context" do
      described_class.on_finish("statusCode" => 200, "headers" => {"Content-Type" => "application/json"})

      expect(gateway).to have_received(:push).with(
        "aws_lambda.response.start",
        kind_of(Datadog::AppSec::Instrumentation::Gateway::DataContainer),
      )
      expect(Datadog::AppSec::Event).to have_received(:record).with(context, request: state[:aws_lambda_request])
      expect(context).to have_received(:export_metrics)
      expect(context).to have_received(:export_request_telemetry)
      expect(Datadog::AppSec::Context).to have_received(:deactivate)
    end

    it "extracts an API Security schema for sampled requests" do
      allow(Datadog::AppSec::APISecurity).to receive_messages(enabled?: true, sample_trace?: true, sample?: true)

      described_class.on_finish("statusCode" => 200)

      expect(context).to have_received(:extract_schema!)
    end

    it "returns an API Gateway response when response inspection blocks" do
      allow(gateway).to receive(:push) do |name, _payload|
        if name == "aws_lambda.response.start"
          throw(Datadog::AppSec::Ext::INTERRUPT, "status_code" => 403, "type" => "json")
        end
      end

      response = described_class.on_finish("statusCode" => 200)

      expect(response).to include("statusCode" => 403)
      expect(context).to have_received(:mark_as_interrupted!)
    end

    it "deactivates the context without affecting the response when exporting metrics fails" do
      allow(context).to receive(:export_metrics).and_raise("metrics failed")

      expect { described_class.on_finish("statusCode" => 200) }.not_to raise_error
      expect(context).to have_received(:export_request_telemetry)
      expect(Datadog::AppSec::Context).to have_received(:deactivate)
    end
  end
end
