require 'datadog/error_tracking/spec_helper'

RSpec.describe 'Error Tracking benchmarks', :memcheck_valgrind_skip do
  error_tracking_test

  with_env 'VALIDATE_BENCHMARK' => 'true'

  benchmarks_to_validate = [
    'error_tracking_simple',
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it('runs without raising errors') { expect_in_fork { load "./benchmarks/#{benchmark}.rb" } }
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it 'tests all expected benchmarks in the benchmarks folder' do
    all_benchmarks = Dir['./benchmarks/error_tracking_*'].map { |it| it.gsub('./benchmarks/', '').gsub('.rb', '') }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
