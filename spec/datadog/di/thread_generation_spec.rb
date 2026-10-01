# frozen_string_literal: true

require "datadog/di/thread_generation"

RSpec.describe Datadog::DI::ThreadGeneration do
  it "returns the same token for the same thread" do
    expect(described_class.current).to eq(described_class.current)
  end

  it "returns a positive integer" do
    expect(described_class.current).to be_an(Integer)
    expect(described_class.current).to be > 0
  end

  it "returns a different token for a different thread" do
    main_token = described_class.current
    other_token = nil
    Thread.new { other_token = described_class.current }.join
    expect(other_token).to be_an(Integer)
    expect(other_token).not_to eq(main_token)
  end

  it "is stable for a thread across calls" do
    tokens = []
    Thread.new do
      3.times { tokens << described_class.current }
    end.join
    expect(tokens.uniq).to eq([tokens.first])
  end
end
