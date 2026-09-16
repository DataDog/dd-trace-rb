# frozen_string_literal: true

require "ostruct"

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/aws_lambda_ric/instrumentation"

RSpec.describe Datadog::Tracing::Contrib::AwsLambdaRic::Instrumentation do
  let(:handler_class) do
    Class.new do
      prepend Datadog::Tracing::Contrib::AwsLambdaRic::Instrumentation

      attr_reader :calls, :response

      def initialize
        @response = +'{"statusCode":200,"body":"ok"}'
      end

      def call_handler(request:, context:)
        @calls = [request, context]
        @response
      end
    end
  end
  let(:handler) { handler_class.new }
  let(:context) do
    OpenStruct.new(
      aws_request_id: "request-1",
      function_name: "MyFunction",
      function_version: "$LATEST",
      invoked_function_arn: "arn:aws:lambda:us-east-1:123456789012:function:MyFunction:alias",
    )
  end

  before do
    allow(Datadog::Tracing::Contrib::AwsLambdaRic::LateActivation).to receive(:patch!)
    allow(Datadog::Tracing::Contrib::AwsLambdaRic::Lifecycle).to receive_messages(
      start: nil,
      finish: nil,
      claim_cold_start: true,
    )
    allow(Datadog::AppSec::Contrib::AwsLambda::Instrumentation).to receive_messages(
      on_start: nil,
      on_finish: nil,
    )
    allow(Datadog::AppSec::Contrib::AwsLambda::Instrumentation).to receive(:catch_interrupt).and_yield
  end

  it "returns the exact marshalled RIC response and emits the serverless placeholder span" do
    result = handler.call_handler(request: {"hello" => "world"}, context: context)

    expect(result).to equal(handler.response)
    expect(handler.calls.first).to eq("hello" => "world")
    expect(span.name).to eq("aws.lambda")
    expect(span.resource).to eq("dd-tracer-serverless-span")
    expect(span.type).to eq("serverless")
    expect(span.get_tag("component")).to eq("aws_lambda_ric")
    expect(span.get_tag("operation")).to eq("invoke")
    expect(span.get_tag("span.kind")).to eq("server")
    expect(span.get_tag("request_id")).to eq("request-1")
    expect(span.get_tag("functionname")).to eq("myfunction")
    expect(span.get_tag("function_arn"))
      .to eq("arn:aws:lambda:us-east-1:123456789012:function:myfunction")
    expect(Datadog::Tracing::Contrib::AwsLambdaRic::Lifecycle).to have_received(:finish).with(
      result,
      span: kind_of(Datadog::Tracing::SpanOperation),
      request_id: "request-1",
      error: nil,
      trace_digest: kind_of(Datadog::Tracing::TraceDigest),
    )
  end

  it "marshals an AppSec blocking response without calling the handler" do
    stub_const("AwsLambda", Module.new)
    stub_const(
      "AwsLambda::Marshaller",
      Class.new do
        def self.marshall_response(_value)
        end
      end,
    )
    allow(AwsLambda::Marshaller).to receive(:marshall_response) { |value| JSON.generate(value) }
    allow(Datadog::AppSec::Contrib::AwsLambda::Instrumentation).to receive(:on_start).and_return(
      "statusCode" => 403,
      "body" => "blocked",
    )

    result = handler.call_handler(request: {}, context: context)

    expect(JSON.parse(result)).to include("statusCode" => 403)
    expect(handler.calls).to be_nil
  end

  it "reports the original handler error while preserving the RIC wrapper" do
    original_error = RuntimeError.new("handler failed")
    wrapper_class = Class.new(StandardError)
    stub_const("LambdaErrors::LambdaError", wrapper_class)
    stub_const("LambdaErrors::LambdaHandlerError", Class.new(wrapper_class))

    failing_handler = Class.new do
      prepend Datadog::Tracing::Contrib::AwsLambdaRic::Instrumentation

      define_method(:call_handler) do |request:, context:|
        raise original_error
      rescue RuntimeError => e
        raise LambdaErrors::LambdaHandlerError, e.message
      end
    end.new

    expect { failing_handler.call_handler(request: {}, context: context) }
      .to raise_error(LambdaErrors::LambdaHandlerError, "handler failed")
    expect(span.get_tag("error.type")).to eq("RuntimeError")
    expect(Datadog::Tracing::Contrib::AwsLambdaRic::Lifecycle).to have_received(:finish).with(
      nil,
      span: kind_of(Datadog::Tracing::SpanOperation),
      request_id: "request-1",
      error: original_error,
      trace_digest: kind_of(Datadog::Tracing::TraceDigest),
    )
  end

  it "does not let AppSec finalization failures affect the handler response" do
    allow(Datadog::AppSec::Contrib::AwsLambda::Instrumentation).to receive(:on_finish).and_raise("AppSec failed")

    expect(handler.call_handler(request: {}, context: context)).to equal(handler.response)
  end
end
