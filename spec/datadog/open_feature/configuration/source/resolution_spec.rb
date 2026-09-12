# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/configuration/source/resolution"

RSpec.describe Datadog::OpenFeature::Configuration::Source::Resolution do
  subject(:resolution) { described_class.new(enabled: enabled, source: "remote_config") }

  let(:enabled) { true }

  it "exposes the selected source" do
    expect(resolution.source).to eq("remote_config")
  end

  it { is_expected.to be_enabled }

  context "when delivery is disabled" do
    let(:enabled) { false }

    it { is_expected.not_to be_enabled }
  end
end
