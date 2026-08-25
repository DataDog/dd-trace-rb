# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenFeature benchmarks" do
  with_env "VALIDATE_BENCHMARK" => "true"

  benchmarks_to_validate = [
    "open_feature_flagevaluation",
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it("runs without raising errors") { expect_in_fork { load "./benchmarks/#{benchmark}.rb" } }
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it "tests all expected benchmarks in the benchmarks folder" do
    all_benchmarks = Dir["./benchmarks/open_feature_*"].map { |it| it.gsub("./benchmarks/", "").gsub(".rb", "") }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
