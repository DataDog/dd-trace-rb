# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/aws_lambda/response"

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Response do
  it "exposes the normalized API Gateway response" do
    response = described_class.from_normalized(
      "status_code" => "201",
      "headers" => {"content-type" => "application/json"},
      "body" => '{"ok":true}',
    )

    expect(response.status).to eq(201)
    expect(response.headers).to eq("content-type" => "application/json")
    expect(response.body).to eq('{"ok":true}')
  end

  it "provides safe defaults for missing values" do
    response = described_class.from_normalized({})

    expect(response.status).to eq(0)
    expect(response.headers).to eq({})
    expect(response.body).to be_nil
  end
end
