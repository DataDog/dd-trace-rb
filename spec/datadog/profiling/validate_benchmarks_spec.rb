# typed: false
require 'datadog/profiling/spec_helper'

RSpec.describe 'Profiling benchmarks', if: (RUBY_VERSION >= '2.4.0') do
  before { skip_if_profiling_not_supported(self) }

  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  describe 'profiler_submission' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_submission.rb' } }
  end

  describe 'profiler_sample_loop' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_sample_loop.rb' } }
  end
end
