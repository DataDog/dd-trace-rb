# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/aws_lambda_ric/patcher"

RSpec.describe Datadog::Tracing::Contrib::AwsLambdaRic::Patcher do
  before do
    stub_const(
      "LambdaHandler",
      Class.new do
        def call_handler(request:, context:)
        end
      end,
    )
    allow(Datadog.configuration.appsec).to receive(:instrument)
  end

  it "prepends the RIC handler instrumentation and enables the Lambda AppSec gateway" do
    described_class.patch

    expect(LambdaHandler.ancestors).to include(Datadog::Tracing::Contrib::AwsLambdaRic::Instrumentation)
    expect(Datadog.configuration.appsec).to have_received(:instrument).with(:aws_lambda)
  end
end
