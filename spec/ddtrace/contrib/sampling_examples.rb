require 'ddtrace/ext/priority'

RSpec.shared_examples_for 'event sample rate' do
  let(:default_event_sample_rate) { nil }

  context 'when not configured' do
    it 'is not included in the tags' do
      expect(span.get_metric(Datadog::Ext::Priority::TAG_EVENT_SAMPLE_RATE)).to eq(default_event_sample_rate)
    end
  end

  context 'when set' do
    let(:configuration_options) { super().merge(event_sample_rate: event_sample_rate) }
    let(:event_sample_rate) { 0.5 }

    it 'is included in the tags' do
      expect(span.get_metric(Datadog::Ext::Priority::TAG_EVENT_SAMPLE_RATE)).to eq(event_sample_rate)
    end
  end
end
