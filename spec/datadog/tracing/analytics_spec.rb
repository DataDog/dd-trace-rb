require 'spec_helper'

require 'datadog/tracing/analytics'
require 'datadog/tracing/span'

RSpec.describe Datadog::Tracing::Analytics do
  describe '.set_sample_rate' do
    subject(:set_sample_rate) { described_class.set_sample_rate(span, sample_rate) }

    let(:span) { instance_double(Datadog::Tracing::Span) }
    let(:sample_rate) { 0.5 }

    before do
      allow(span).to receive(:set_metric) unless span.nil?
      set_sample_rate
    end

    context 'given span that is' do
      context 'nil' do
        let(:span) { nil }

        it { expect { set_sample_rate }.to_not raise_error }
      end
    end

    context 'given sample rate that is' do
      context 'nil' do
        let(:sample_rate) { nil }

        it { expect(span).to_not have_received(:set_metric) }
      end

      context 'a String' do
        let(:sample_rate) { '1.0' }

        it { expect(span).to_not have_received(:set_metric) }
      end

      context 'a Float' do
        let(:sample_rate) { 1.0 }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE, sample_rate)
        end
      end
    end
  end

  describe '.set_measured' do
    subject(:set_measured) { described_class.set_measured(span) }

    let(:span) { instance_double(Datadog::Tracing::Span) }

    before do
      allow(span).to receive(:set_metric) unless span.nil?
      set_measured
    end

    context 'given a nil span' do
      let(:span) { nil }

      it { expect { set_measured }.to_not raise_error }
    end

    context 'given only a span' do
      it do
        expect(span).to have_received(:set_metric)
          .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 1)
      end
    end

    context 'given a span and value that is' do
      subject(:set_measured) { described_class.set_measured(span, value) }

      context 'nil' do
        let(:value) { nil }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 0)
        end
      end

      context 'true' do
        let(:value) { true }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 1)
        end
      end

      context 'false' do
        let(:value) { false }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 0)
        end
      end

      context 'a String' do
        let(:value) { 'true' }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 0)
        end
      end

      context 'an Integer' do
        let(:value) { 1 }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, 1)
        end
      end

      context 'a Float' do
        let(:value) { 1.0 }

        it do
          expect(span).to have_received(:set_metric)
            .with(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED, value)
        end
      end
    end
  end
end
