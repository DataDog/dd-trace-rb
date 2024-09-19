require 'spec_helper'
require 'datadog/tracing/sampling/shared_examples'

require 'datadog/tracing/sampling/rate_by_service_sampler'
require 'datadog/tracing/sampling/rate_sampler'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Sampling::RateByServiceSampler do
  subject(:sampler) { described_class.new }

  describe '#initialize' do
    context 'with defaults' do
      it { expect(sampler.default_key).to eq(described_class::DEFAULT_KEY) }
      it { expect(sampler.length).to eq 1 }
      it { expect(sampler.default_sampler.sample_rate).to eq 1.0 }
    end

    context 'given a default rate' do
      subject(:sampler) { described_class.new(default_rate) }

      let(:default_rate) { 0.1 }

      it { expect(sampler.default_sampler.sample_rate).to eq default_rate }
    end
  end

  describe '#resolve' do
    subject(:resolve) { sampler.resolve(trace) }

    let(:trace) { instance_double(Datadog::Tracing::TraceOperation, service: service_name) }
    let(:service_name) { 'my-service' }

    context 'when the sampler is not configured with an :env option' do
      it { is_expected.to eq("service:#{service_name},env:") }
    end

    context 'when the sampler is configured with an :env option' do
      let(:sampler) { described_class.new(1.0, env: env) }

      context 'that is a String' do
        let(:env) { 'my-env' }

        it { is_expected.to eq("service:#{service_name},env:#{env}") }
      end

      context 'that is a Proc' do
        let(:env) { proc { 'my-env' } }

        it { is_expected.to eq("service:#{service_name},env:my-env") }
      end
    end
  end

  describe '#update' do
    subject(:update) { sampler.update(rate_by_service) }

    let(:samplers) { sampler.instance_variable_get(:@samplers) }

    include_context 'health metrics'

    context 'when new rates' do
      context 'describe a new bucket' do
        let(:new_key) { 'service:new-service,env:my-env' }
        let(:new_rate) { 0.5 }
        let(:rate_by_service) { { new_key => new_rate } }

        before { update }

        it 'adds a new sampler' do
          expect(samplers).to include(
            described_class::DEFAULT_KEY => kind_of(Datadog::Tracing::Sampling::RateSampler),
            new_key => kind_of(Datadog::Tracing::Sampling::RateSampler)
          )

          expect(samplers[new_key].sample_rate).to eq(new_rate)
        end
      end

      context 'describe an existing bucket' do
        let(:existing_key) { 'service:existing-service,env:my-env' }
        let(:new_rate) { 0.5 }
        let(:rate_by_service) { { existing_key => new_rate } }

        before do
          sampler.update({ existing_key => 1.0 })
          update
        end

        it 'updates the existing sampler' do
          expect(samplers).to include(
            described_class::DEFAULT_KEY => kind_of(Datadog::Tracing::Sampling::RateSampler),
            existing_key => kind_of(Datadog::Tracing::Sampling::RateSampler)
          )

          expect(samplers[existing_key].sample_rate).to eq(new_rate)

          # Expect metrics twice; one for setup, one for test.
          expect(health_metrics).to have_received(:sampling_service_cache_length).with(2).twice
        end
      end

      context 'omit an existing bucket' do
        let(:old_key) { 'service:old-service,env:my-env' }
        let(:rate_by_service) { {} }

        before do
          sampler.update({ old_key => 1.0 })
          update
        end

        it 'updates the existing sampler' do
          expect(samplers).to include(
            described_class::DEFAULT_KEY => kind_of(Datadog::Tracing::Sampling::RateSampler)
          )

          expect(samplers.keys).to_not include(old_key)
          expect(health_metrics).to have_received(:sampling_service_cache_length).with(1)
        end
      end

      context 'with a default key update' do
        let(:rate_by_service) { { default_key => 0.123 } }
        let(:default_key) { 'service:,env:' }

        it 'updates the existing sampler' do
          update

          expect(samplers).to match('service:,env:' => have_attributes(sample_rate: 0.123))
          expect(health_metrics).to have_received(:sampling_service_cache_length).with(1)
        end
      end
    end
  end
end
