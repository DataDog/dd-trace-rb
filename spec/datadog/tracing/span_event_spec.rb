require 'spec_helper'
require 'support/object_helpers'

require 'datadog/tracing/span_event'

RSpec.describe Datadog::Tracing::SpanEvent do
  subject(:span_event) { described_class.new(name, attributes: attributes, time_unix_nano: time_unix_nano) }

  let(:name) { nil }
  let(:attributes) { nil }
  let(:time_unix_nano) { nil }

  describe '::new' do
    context 'by default' do
      let(:name) { 'This happened!' }

      it do
        expect(span_event.name).to eq(name)
        expect(span_event.attributes).to eq({})
        expect(span_event.time_unix_nano / 1e9).to be_within(1).of(Time.now.to_f)
      end
    end

    context 'given' do
      context ':attributes' do
        let(:attributes) { { tag: 'value' } }
        it { is_expected.to have_attributes(attributes: attributes) }
      end

      context ':time_unix_nano' do
        let(:time_unix_nano) { 30000 }
        it { is_expected.to have_attributes(time_unix_nano: time_unix_nano) }
      end
    end
  end

  describe '#to_hash' do
    subject(:to_hash) { span_event.to_hash }
    let(:name) { 'Another Event!' }

    context 'with required fields' do
      it { is_expected.to eq({ name: name, time_unix_nano: span_event.time_unix_nano }) }
    end

    context 'with timestamp' do
      let(:time_unix_nano) { 25 }
      it { is_expected.to include(time_unix_nano: 25) }
    end

    context 'when attributes is set' do
      let(:attributes) { { 'event.name' => 'test_event', 'event.id' => 1, 'nested' => [true, [2, 3], 'val'] } }
      it {
        is_expected.to include(
          attributes: { 'event.name' => 'test_event', 'event.id' => '1', 'nested' => '[true, [2, 3], "val"]' }
        )
      }
    end
  end
end
