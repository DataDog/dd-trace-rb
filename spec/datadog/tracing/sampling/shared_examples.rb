require 'datadog/tracing/trace_operation'

RSpec.shared_examples 'sampler with sample rate' do |sample_rate|
  subject(:sampler_sample_rate) { sampler.sample_rate(trace_op) }

  let(:trace_op) { Datadog::Tracing::TraceOperation.new }

  it { is_expected.to eq(sample_rate) }
end
