require 'datadog/profiling/spec_helper'

RSpec.describe 'Profiling benchmarks' do
  before { skip_if_profiling_not_supported(self) }

  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  describe 'profiler_sample_loop_v2' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_sample_loop_v2.rb' } }
  end

  describe 'profiler_http_transport' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_http_transport.rb' } }
  end

  describe 'profiler_sample_serialize' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_sample_serialize.rb' } }
  end
end
