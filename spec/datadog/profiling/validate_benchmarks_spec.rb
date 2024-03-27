require 'datadog/profiling/spec_helper'

RSpec.describe 'Profiling benchmarks', if: (RUBY_VERSION >= '2.4.0') do
  before { skip_if_profiling_not_supported(self) }

  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  [
    'profiler_sample_loop_v2',
    'profiler_http_transport',
    'profiler_sample_serialize',
    'profiler_memory_sample_serialize',
    'profiler_gc'
  ].each do |benchmark|
    describe benchmark do
      it('runs without raising errors') { expect_in_fork { load "./benchmarks/#{benchmark}.rb" } }
    end
  end
end
