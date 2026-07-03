require "datadog/di/spec_helper"

RSpec.describe "Dynamic instrumentation benchmarks", :memcheck_valgrind_skip do
  di_test

  with_env "VALIDATE_BENCHMARK" => "true"

  benchmarks_to_validate = [
    "di_instrument", "di_method_probe_wrapper", "di_snapshot",
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      timeout = case benchmark
                when 'di_snapshot' then 20
                when 'di_method_probe_wrapper' then 60
                else 10
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
