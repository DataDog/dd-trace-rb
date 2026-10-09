# frozen_string_literal: true

require "spec_helper"
require_relative "../../../tasks/lib/test_batching/samples"

RSpec.describe TestBatching::Samples do
  it "reports the median and 90th percentile of odd-sized values" do
    samples = described_class.new([30, 10, 20])

    expect(samples.to_h).to eq({"p50_seconds" => 20, "p90_seconds" => 30, "samples" => 3})
  end

  it "averages the middle pair for an even count" do
    samples = described_class.new([10, 20, 30, 40])

    expect(samples.to_h).to eq({"p50_seconds" => 25.0, "p90_seconds" => 40, "samples" => 4})
  end

  it "rounds to milliseconds when serializing" do
    samples = described_class.new([10.12345, 20.0, 30.5])

    expect(samples.to_h).to eq({"p50_seconds" => 20.0, "p90_seconds" => 30.5, "samples" => 3})
  end
end
