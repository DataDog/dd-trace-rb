# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/evaluator_capabilities"

RSpec.describe Datadog::OpenFeature::EvaluatorCapabilities do
  it "does not advertise unsupported dependent flags" do
    expect(described_class.supported).to eq([])
  end
end
