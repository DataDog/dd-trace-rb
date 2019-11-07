require 'spec_helper'

require 'ddtrace/sampling/matcher'
require 'ddtrace/sampling/rule'

RSpec.describe Datadog::Sampling::Rule do
  let(:span) { Datadog::Span.new(nil, span_name, service: span_service) }
  let(:span_name) { 'operation.name' }
  let(:span_service) { nil }

  describe '#sample' do
    subject(:sample) { rule.sample(span) }
    let(:rule) { described_class.new(matcher, sampler) }

    let(:matcher) { instance_double(Datadog::Sampling::Matcher) }
    let(:matched) { true }

    before do
      allow(matcher).to receive(:match?).with(span).and_return(matched)
    end

    let(:sampler) { instance_double(Datadog::Sampler) }
    let(:sampled) { true }
    let(:sample_rate) { double }

    before do
      allow(sampler).to receive(:sample?).with(span).and_return(sampled)
      allow(sampler).to receive(:sample_rate).with(span).and_return(sample_rate)
    end

    shared_examples 'span not matching rule' do
      it { is_expected.to eq(nil) }
    end

    shared_examples 'span rejected by sampler' do
      it { is_expected.to eq([false, sample_rate]) }
    end

    shared_examples 'span sampled' do
      it { is_expected.to eq([true, sample_rate]) }
    end

    context 'with matching span' do
      let(:matched) { true }

      context 'and sampled' do
        let(:sampled) { true }
        it_behaves_like 'span sampled'
      end

      context 'and not sampled' do
        let(:sampled) { false }
        it_behaves_like 'span rejected by sampler'
      end

      context 'when sampler errs' do
        before do
          allow(sampler).to receive(:sample?).with(span).and_raise(StandardError)
          allow(sampler).to receive(:sample_rate).with(span).and_raise(StandardError)
        end

        it_behaves_like 'span not matching rule'
      end
    end

    context 'with span not matching' do
      let(:matched) { false }
      it_behaves_like 'span not matching rule'
    end

    context 'when matcher errs' do
      before do
        allow(matcher).to receive(:match?).and_raise(StandardError)
      end

      it_behaves_like 'span not matching rule'
    end
  end
end
