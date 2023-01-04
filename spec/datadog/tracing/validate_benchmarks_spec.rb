# typed: false

require 'datadog/profiling/spec_helper'

RSpec.describe 'Tracing benchmarks', if: (RUBY_VERSION >= '2.4.0') do
  around do |example|
    ClimateControl.modify('VALIDATE_BENCHMARK' => 'true') do
      example.run
    end
  end

  describe 'tracing_http_transport' do
    it('runs without raising errors') { expect_in_fork { load './benchmarks/tracing_http_transport.rb' } }
  end
end
