# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/aws_lambda/response_normalizer"

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::ResponseNormalizer do
  it "normalizes all API Gateway response fields" do
    response = {
      "statusCode" => 200,
      "headers" => {"content-type" => "application/json"},
      "body" => '{"ok":true}',
      "isBase64Encoded" => false,
    }

    expect(described_class.normalize(response)).to eq(
      "status_code" => 200,
      "headers" => {"content-type" => "application/json"},
      "body" => '{"ok":true}',
      "base64_encoded" => false,
    )
  end

  it "merges multi-value headers with precedence" do
    response = {
      "statusCode" => 200,
      "headers" => {"content-type" => "text/html", "set-cookie" => "a=1"},
      "multiValueHeaders" => {"set-cookie" => ["a=1", "b=2"]},
    }

    expect(described_class.normalize(response)["headers"]).to eq(
      "content-type" => "text/html",
      "set-cookie" => ["a=1", "b=2"],
    )
  end

  it "drops nil fields and ignores non-API responses" do
    expect(described_class.normalize("response")).to eq({})
    expect(described_class.normalize("statusCode" => 204, "body" => nil)).to eq("status_code" => 204)
  end
end
