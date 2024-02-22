require 'spec_helper'

RSpec.describe 'Tracing benchmarks' do
  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  describe 'tracing_trace' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/tracing_trace.rb' } }
  end
end
