require 'spec_helper'
require 'datadog/tracing/sampling/shared_examples'

require 'logger'

require 'datadog/core'
require 'datadog/tracing/sampling/all_sampler'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Sampling::AllSampler do
  subject(:sampler) { described_class.new }

  before { Datadog.logger.level = Logger::FATAL }

  after { Datadog.logger.level = Logger::WARN }

  describe '#sample!' do
    let(:traces) { Array.new(3) { |i| Datadog::Tracing::TraceOperation.new(id: i) } }

    it 'samples all span operations' do
      traces.each do |trace|
        expect(sampler.sample!(trace)).to be true
        expect(trace.sampled?).to be true
      end
    end
  end

  it_behaves_like 'sampler with sample rate', 1.0
end
