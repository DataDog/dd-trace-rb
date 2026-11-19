# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/agentless/response"

RSpec.describe Datadog::OpenFeature::Agentless::Response do
  subject(:response) do
    described_class.new(
      status: 200,
      etag: "etag",
      body: "body",
      error: error,
      flag_selection_ignored: "invalid_tag",
    )
  end

  let(:error) { StandardError.new("failure") }

  it "exposes the request result" do
    expect(response.status).to eq(200)
    expect(response.etag).to eq("etag")
    expect(response.body).to eq("body")
    expect(response.error).to equal(error)
    expect(response.flag_selection_ignored).to eq("invalid_tag")
  end
end
