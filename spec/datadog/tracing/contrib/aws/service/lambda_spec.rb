# frozen_string_literal: true

require "datadog/tracing/contrib/aws/service/lambda"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Lambda do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:lambda_service) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  shared_examples "sets the function arn" do |expected_arn|
    it "sets the function arn tag" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_FUNCTION_ARN, expected_arn)
    end
  end

  shared_examples "does not set the function arn" do
    it "does not set the function arn tag" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_FUNCTION_ARN, anything)
    end
  end

  context "with a full function ARN" do
    let(:params) { {function_name: "arn:aws:lambda:us-east-1:123456789012:function:my-function"} }

    include_examples "sets the function arn", "arn:aws:lambda:us-east-1:123456789012:function:my-function"
  end

  context "with a qualified function ARN" do
    let(:params) { {function_name: "arn:aws:lambda:us-east-1:123456789012:function:my-function:my-alias"} }

    include_examples "sets the function arn", "arn:aws:lambda:us-east-1:123456789012:function:my-function"
  end

  context "with a function ARN in another partition" do
    let(:params) { {function_name: "arn:aws-cn:lambda:cn-north-1:123456789012:function:my-function:3"} }

    include_examples "sets the function arn", "arn:aws-cn:lambda:cn-north-1:123456789012:function:my-function"
  end

  context "with a function name" do
    let(:params) { {function_name: "my-function"} }

    include_examples "does not set the function arn"
  end

  context "with a partial ARN" do
    let(:params) { {function_name: "123456789012:function:my-function"} }

    include_examples "does not set the function arn"
  end

  context "with an ARN that is not a function ARN" do
    let(:params) { {function_name: "arn:aws:lambda:us-east-1:123456789012:layer:my-layer:1"} }

    include_examples "does not set the function arn"
  end

  context "without function_name" do
    include_examples "does not set the function arn"
  end
end
