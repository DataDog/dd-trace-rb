# typed: false
RSpec.describe 'Profiling benchmarks', if: (RUBY_VERSION >= '2.4.0' && PlatformHelpers.supports_fork?) do
  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  describe 'profiler_submission' do
    before { skip('TODO: Generate new dump file.') }
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_submission.rb' } }
  end

  describe 'profiler_sample_loop' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/profiler_sample_loop.rb' } }
  end
end
