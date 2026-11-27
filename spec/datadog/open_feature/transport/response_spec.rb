# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/transport/response"

RSpec.describe Datadog::OpenFeature::Transport::Response do
  subject(:response) { described_class.new(code: 202) }

  it "exposes status without retaining a payload or exception" do
    expect(response).to be_ok
    expect(response.payload).to be_nil
    expect(response).not_to be_internal_error
    expect(response).not_to be_pre_send
  end
end
