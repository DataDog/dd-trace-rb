# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/aws_lambda/event_normalizer"

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::EventNormalizer do
  it "normalizes API Gateway v1 events" do
    event = {
      "httpMethod" => "POST",
      "path" => "/v1",
      "headers" => {"host" => "example.com"},
      "requestContext" => {"identity" => {"sourceIp" => "192.0.2.1"}},
    }

    expect(described_class.normalize(event)).to include(
      "method" => "POST",
      "path" => "/v1",
      "source_ip" => "192.0.2.1",
    )
  end

  it "normalizes API Gateway v2 events" do
    event = {
      "version" => "2.0",
      "rawPath" => "/v2",
      "rawQueryString" => "page=1",
      "requestContext" => {"http" => {"method" => "GET", "sourceIp" => "192.0.2.2"}},
    }

    expect(described_class.normalize(event)).to include(
      "method" => "GET",
      "path" => "/v2",
      "query_string" => "page=1",
      "source_ip" => "192.0.2.2",
    )
  end

  it "gracefully ignores non-HTTP events" do
    expect(described_class.normalize("event")).to eq({})
  end
end
