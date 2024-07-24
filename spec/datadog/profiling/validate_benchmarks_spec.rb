require 'datadog/profiling/spec_helper'

RSpec.describe 'Profiling benchmarks' do
  before { skip_if_profiling_not_supported(self) }

  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  benchmarks_to_validate = [
    'profiler_sample_loop_v2',
    'profiler_http_transport',
    'profiler_sample_serialize',
    'profiler_memory_sample_serialize',
    'profiler_gc',
    'profiler_hold_resume_interruptions'
  ].freeze

  benchmarks_to_validate.each do |benchmark|
    describe benchmark do
      it('runs without raising errors') { expect_in_fork { load "./benchmarks/#{benchmark}.rb" } }
    end
  end

  # This test validates that we don't forget to add new benchmarks to benchmarks_to_validate
  it 'tests all expected benchmarks in the benchmarks folder' do
    all_benchmarks = Dir['./benchmarks/profiler_*'].map { |it| it.gsub('./benchmarks/', '').gsub('.rb', '') }

    expect(benchmarks_to_validate).to contain_exactly(*all_benchmarks)
  end
end
