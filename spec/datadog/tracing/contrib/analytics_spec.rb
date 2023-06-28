require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/analytics'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span'
require 'datadog/tracing/contrib/analytics'

RSpec.describe Datadog::Tracing::Contrib::Analytics do
  describe '::enabled?' do
    context 'when flag is not provided' do
      subject(:enabled?) { described_class.enabled? }

      it { is_expected.to be false }
    end

    context 'when flag is nil' do
      subject(:enabled?) { described_class.enabled?(nil) }

      it { is_expected.to be false }
    end

    context 'when flag is true' do
      subject(:enabled?) { described_class.enabled?(true) }

      it { is_expected.to be true }
    end

    context 'when flag is false' do
      subject(:enabled?) { described_class.enabled?(false) }

      it { is_expected.to be false }
    end
  end

  describe '::set_sample_rate' do
    subject(:set_sample_rate) { described_class.set_sample_rate(span, sample_rate) }

    let(:span) { instance_double(Datadog::Tracing::Span) }

    context 'when sample rate is nil' do
      let(:sample_rate) { nil }

      it 'does not set the tag' do
        expect(span).to_not receive(:set_metric)
        set_sample_rate
      end
    end

    context 'when a sample rate is given' do
      let(:sample_rate) { 0.5 }

      it 'sets the tag' do
        expect(span).to receive(:set_metric)
          .with(
            Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE,
            sample_rate
          )

        set_sample_rate
      end
    end
  end

  describe '::set_measured' do
    subject(:set_measured) { described_class.set_measured(span) }

    let(:span) { instance_double(Datadog::Tracing::Span) }

    before do
      allow(Datadog::Tracing::Analytics).to receive(:set_measured)
      set_measured
    end

    context 'when only a span is given' do
      it 'sets measured as true' do
        expect(Datadog::Tracing::Analytics).to have_received(:set_measured)
          .with(span, true)
      end
    end

    context 'when a span and value is given' do
      subject(:set_measured) { described_class.set_measured(span, value) }

      let(:value) { double('value') }

      it 'sets measured as true' do
        expect(Datadog::Tracing::Analytics).to have_received(:set_measured)
          .with(span, value)
      end
    end
  end
end
