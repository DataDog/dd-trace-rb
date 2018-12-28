require 'spec_helper'

require 'ddtrace/contrib/sampling'

RSpec.describe Datadog::Contrib::Sampling do
  describe '::set_event_sample_rate' do
    subject(:set_event_sample_rate) { described_class.set_event_sample_rate(span, sample_rate) }
    let(:span) { instance_double(Datadog::Span) }

    context 'when sample rate is nil' do
      let(:sample_rate) { nil }

      it 'does not set the tag' do
        expect(span).to_not receive(:set_metric)
        set_event_sample_rate
      end
    end

    context 'when a sample rate is given' do
      let(:sample_rate) { 0.5 }

      it 'sets the tag' do
        expect(span).to receive(:set_metric)
          .with(
            Datadog::Ext::Priority::TAG_EVENT_SAMPLE_RATE,
            sample_rate
          )

        set_event_sample_rate
      end
    end
  end
end
