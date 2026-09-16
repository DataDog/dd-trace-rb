# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/aws_lambda/request"

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Request do
  subject(:request) { described_class.from_normalized(event) }

  let(:event) do
    {
      "headers" => {
        "Host" => "example.com",
        "User-Agent" => "TestBot/1.0",
        "Accept" => "text/html",
      },
      "source_ip" => "192.0.2.1",
      "method" => "GET",
      "path" => "/users/123",
    }
  end

  it "normalizes the request properties used by AppSec" do
    expect(request.headers).to eq(
      "host" => "example.com",
      "user-agent" => "TestBot/1.0",
      "accept" => "text/html",
    )
    expect(request.host).to eq("example.com")
    expect(request.user_agent).to eq("TestBot/1.0")
    expect(request.remote_addr).to eq("192.0.2.1")
    expect(request.request_method).to eq("GET")
    expect(request.path).to eq("/users/123")
  end

  it "accepts events without optional request data" do
    request = described_class.from_normalized({})

    expect(request.headers).to eq({})
    expect(request.host).to be_nil
    expect(request.remote_addr).to be_nil
  end
end
