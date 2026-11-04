# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/evaluator_capabilities"

RSpec.describe Datadog::OpenFeature::EvaluatorCapabilities do
  subject(:supported) { described_class.dependent_flags? }

  [[], ["unknown"], ["dependent-flag-variant-key-v1"], ["unknown", "dependent-flag-variant-key-v1"]].each do |capabilities|
    context "when native capabilities are #{capabilities.inspect}" do
      before { allow(Datadog::Core::FeatureFlags).to receive(:evaluator_capabilities).and_return(capabilities) }

      it { is_expected.to eq(capabilities.include?("dependent-flag-variant-key-v1")) }
    end
  end

  it "fails closed with an older extension" do
    allow(Datadog::Core::FeatureFlags).to receive(:respond_to?).with(:evaluator_capabilities).and_return(false)
    expect(supported).to be(false)
  end

  it "fails closed when discovery raises" do
    allow(Datadog::Core::FeatureFlags).to receive(:evaluator_capabilities).and_raise(StandardError)
    expect(supported).to be(false)
  end
end
