require "datadog/di/spec_helper"

# rubocop:disable Style/BlockComments

=begin benchmarks require DI code to be merged
RSpec.describe "Dynamic instrumentation benchmarks", :memcheck_valgrind_skip do
  di_test

  around do |example|
    ClimateControl.modify("VALIDATE_BENCHMARK" => "true") do
      example.run
    end
  end

  benchmarks_to_validate = [
    "di_instrument",
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it("runs without raising errors") { expect_in_fork { load "./benchmarks/#{benchmark}.rb" } }
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it "tests all expected benchmarks in the benchmarks folder" do
    all_benchmarks = Dir["./benchmarks/di_*"].map { |it| it.gsub("./benchmarks/", "").gsub(".rb", "") }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
=end

# rubocop:enable Style/BlockComments
