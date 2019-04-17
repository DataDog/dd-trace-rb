require 'spec_helper'
require 'ddtrace/span'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(tracer, name, context: context) }
  let(:tracer) { get_test_tracer }
  let(:context) { Datadog::Context.new }
  let(:name) { 'my.span' }

  describe '#set_tag' do
    subject(:set_tag) { span.set_tag(key, value) }
    before { set_tag }

    context 'given Datadog::Ext::Analytics::TAG_ENABLED' do
      let(:key) { Datadog::Ext::Analytics::TAG_ENABLED }
      let(:value) { true }

      it 'sets the analytics sample rate' do
        expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0)
        expect(span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
      end
    end

    context 'given Datadog::Ext::Analytics::TAG_SAMPLE_RATE' do
      let(:key) { Datadog::Ext::Analytics::TAG_SAMPLE_RATE }
      let(:value) { 0.5 }

      it 'sets the analytics sample rate' do
        expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(value)
        expect(span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
      end
    end

    context 'given Datadog::Ext::ForcedTracing::TAG_KEEP' do
      let(:key) { Datadog::Ext::ForcedTracing::TAG_KEEP }

      context 'with nil value' do
        # This could be `nil`, or any other value, as long as it isn't "false"
        let(:value) { nil }

        it 'sets the correct sampling priority' do
          expect(context.sampling_priority).to eq(Datadog::Ext::Priority::USER_KEEP)
        end

        it 'sets the correct tag' do
          expect(span.get_tag(Datadog::Ext::ForcedTracing::TAG_KEEP)).to eq('')
        end
      end

      context 'with true value' do
        # We only check for `== false`, but test with `true` to be sure it works
        let(:value) { true }

        it 'sets the correct sampling priority' do
          expect(context.sampling_priority).to eq(Datadog::Ext::Priority::USER_KEEP)
        end

        it 'sets the correct tag' do
          expect(span.get_tag(Datadog::Ext::ForcedTracing::TAG_KEEP)).to eq('true')
        end
      end

      context 'with false value' do
        let(:value) { false }

        it 'does not set the sampling priority' do
          expect(context.sampling_priority).to_not eq(Datadog::Ext::Priority::USER_KEEP)
        end

        it 'sets the correct tag' do
          expect(span.get_tag(Datadog::Ext::ForcedTracing::TAG_KEEP)).to eq('false')
        end
      end
    end

    context 'given Datadog::Ext::ForcedTracing::TAG_DROP' do
      let(:key) { Datadog::Ext::ForcedTracing::TAG_DROP }

      context 'with nil value' do
        # This could be `nil`, or any other value, as long as it isn't "false"
        let(:value) { nil }

        it 'sets the correct sampling priority' do
          expect(context.sampling_priority).to eq(Datadog::Ext::Priority::USER_REJECT)
        end

        it 'sets the correct tag' do
          expect(span.get_tag(Datadog::Ext::ForcedTracing::TAG_DROP)).to eq('')
        end
      end

      context 'with true value' do
        # We only check for `== false`, but test with `true` to be sure it works
        let(:value) { true }

        it 'sets the correct sampling priority' do
          expect(context.sampling_priority).to eq(Datadog::Ext::Priority::USER_REJECT)
        end

        it 'sets the correct tag' do
          expect(span.get_tag(Datadog::Ext::ForcedTracing::TAG_DROP)).to eq('true')
        end
      end

      context 'with false value' do
        let(:value) { false }

        it 'does not set the sampling priority' do
          expect(context.sampling_priority).to_not eq(Datadog::Ext::Priority::USER_REJECT)
        end

        it 'sets the correct tag' do
          expect(span.get_tag(Datadog::Ext::ForcedTracing::TAG_DROP)).to eq('false')
        end
      end
    end
  end
end
