# typed: false
require 'spec_helper'

require 'ddtrace/sampling/matcher'
require 'ddtrace/sampling/rule'

RSpec.describe Datadog::Sampling::Rule do
  let(:span_op) { Datadog::SpanOperation.new(span_name, service: span_service) }
  let(:span_name) { 'operation.name' }
  let(:span_service) { nil }

  let(:rule) { described_class.new(matcher, sampler) }
  let(:matcher) { instance_double(Datadog::Sampling::Matcher) }
  let(:sampler) { instance_double(Datadog::Sampler) }

  describe '#match?' do
    subject(:match) { rule.match?(span_op) }

    let(:matched) { true }

    before do
      allow(matcher).to receive(:match?).with(span_op).and_return(matched)
    end

    context 'with matching span operation' do
      let(:matched) { true }

      it { is_expected.to eq(true) }
    end

    context 'with span operation not matching' do
      let(:matched) { false }

      it { is_expected.to eq(false) }
    end

    context 'when matcher errs' do
      let(:error) { StandardError }

      before do
        allow(matcher).to receive(:match?).and_raise(error)

        expect(Datadog.logger).to receive(:error)
          .with(a_string_including("Matcher failed. Cause: #{error}"))
      end

      it { is_expected.to be nil }
    end
  end

  describe '#sample?' do
    subject(:sample) { rule.sample?(span_op) }

    let(:sample) { double }

    before do
      allow(sampler).to receive(:sample?).with(span_op).and_return(sample)
    end

    it { is_expected.to be(sample) }
  end

  describe '#sample_rate' do
    subject(:sample_rate) { rule.sample_rate(span_op) }

    let(:sample_rate) { double }

    before do
      allow(sampler).to receive(:sample_rate).with(span_op).and_return(sample_rate)
    end

    it { is_expected.to be(sample_rate) }
  end
end
