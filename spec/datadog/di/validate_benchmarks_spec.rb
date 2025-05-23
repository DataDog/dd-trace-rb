require "datadog/di/spec_helper"

RSpec.describe "Dynamic instrumentation benchmarks", :memcheck_valgrind_skip do
  di_test

  around do |example|
    ClimateControl.modify("VALIDATE_BENCHMARK" => "true") do
      example.run
    end
  end

  benchmarks_to_validate = [
    "di_instrument", "di_snapshot",
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      timeout = if benchmark == 'di_snapshot'
        20
      else
        10
      end
      it "runs without raising errors" do
        expect_in_fork(timeout_seconds: timeout) do
          load "./benchmarks/#{benchmark}.rb"
        end
      end
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it "tests all expected benchmarks in the benchmarks folder" do
    all_benchmarks = Dir["./benchmarks/di_*"].map do |it|
      it.gsub("./benchmarks/", "").gsub(".rb", "")
    end

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
