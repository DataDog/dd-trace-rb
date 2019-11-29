require 'spec_helper'
require 'ddtrace/ext/forced_tracing'
require 'ddtrace/span'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(tracer, name, context: context) }
  let(:tracer) { get_test_tracer }
  let(:context) { Datadog::Context.new }
  let(:name) { 'my.span' }

  describe '#clear_tag' do
    subject(:clear_tag) { span.clear_tag(key) }
    let(:key) { 'key' }

    before { span.set_tag(key, value) }
    let(:value) { 'value' }

    it do
      expect { subject }.to change { span.get_tag(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      subject
      expect(span.instance_variable_get(:@meta)).to_not have_key(key)
    end
  end

  describe '#clear_metric' do
    subject(:clear_metric) { span.clear_metric(key) }
    let(:key) { 'key' }

    before { span.set_metric(key, value) }
    let(:value) { 1.0 }

    it do
      expect { subject }.to change { span.get_metric(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      subject
      expect(span.instance_variable_get(:@metrics)).to_not have_key(key)
    end
  end

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

    shared_examples 'setting sampling priority tag' do |key, expected_value|
      context "given #{key}" do
        let(:key) { key }

        context 'with nil value' do
          # This could be `nil`, or any other value, as long as it isn't "false"
          let(:value) { nil }

          it 'sets the correct sampling priority' do
            expect(context.sampling_priority).to eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end

        context 'with true value' do
          # We only check for `== false`, but test with `true` to be sure it works
          let(:value) { true }

          it 'sets the correct sampling priority' do
            expect(context.sampling_priority).to eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end

        context 'with false value' do
          let(:value) { false }

          it 'does not set the sampling priority' do
            expect(context.sampling_priority).to_not eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end
      end
    end

    # TODO: Remove when ForcedTracing is fully deprecated
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ForcedTracing::TAG_KEEP,
                    Datadog::Ext::Priority::USER_KEEP)
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ForcedTracing::TAG_DROP,
                    Datadog::Ext::Priority::USER_REJECT)

    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ManualTracing::TAG_KEEP,
                    Datadog::Ext::Priority::USER_KEEP)
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ManualTracing::TAG_DROP,
                    Datadog::Ext::Priority::USER_REJECT)
  end
end
