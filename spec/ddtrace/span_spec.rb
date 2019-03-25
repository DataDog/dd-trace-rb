require 'spec_helper'

require 'ddtrace/span'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(tracer, name) }
  let(:tracer) { get_test_tracer }
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
  end
end
