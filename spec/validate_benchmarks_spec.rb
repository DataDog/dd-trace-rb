require 'spec_helper'

RSpec.describe 'Tracing benchmarks' do
  before { skip('Spec requires Ruby VM supporting fork') unless PlatformHelpers.supports_fork? }

  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  %w(
    gem_loading
    profiler_allocation
    profiler_gc
    profiler_hold_resume_interruptions
    profiler_http_transport
    profiler_memory_sample_serialize
    profiler_sample_loop_v2
    profiler_sample_serialize
    tracing_trace
  ).each do |benchmark|
    describe benchmark do
      it 'runs without raising errors' do
        expect_in_fork do
          load "./benchmarks/#{benchmark}.rb"
        end
      end
    end
  end
end
