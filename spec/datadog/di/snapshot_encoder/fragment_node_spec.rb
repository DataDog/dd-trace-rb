require "datadog/di/spec_helper"
require "datadog/di/snapshot_encoder"

RSpec.describe Datadog::DI::SnapshotEncoder::FragmentNode do
  subject(:node) { described_class.new(fragment) }

  let(:fragment) { "\"caf\u00e9\"" }

  it "holds the fragment and measures it in bytes" do
    expect(node.fragment).to equal fragment
    expect(node.size).to eq 7
  end
end
