require 'spec_helper'
require 'support/object_helpers'

require 'datadog/tracing/span_link'

RSpec.describe Datadog::Tracing::SpanLink do
  subject(:span_link) { described_class.new(**options) }
  let(:options) { {} }

  describe '::new' do
    context 'by default' do
      it do
        is_expected.to have_attributes(
          span_id: nil,
          attributes: nil,
          trace_id: nil,
          trace_flags: nil,
          trace_state: nil,
        )
      end

      it { is_expected.to be_frozen }
    end

    context 'given' do
      context ':span_id' do
        let(:options) { { span_id: span_id } }
        let(:span_id) { Datadog::Tracing::Utils.next_id }

        it { is_expected.to have_attributes(span_id: span_id) }
      end

      context ':attributes' do
        let(:options) { { attributes: attributes } }
        let(:attributes) { { tag: 'value' } }

        it { is_expected.to have_attributes(attributes: be_a_frozen_copy_of(attributes)) }
      end

      context ':trace_id' do
        let(:options) { { trace_id: trace_id } }
        let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }

        it { is_expected.to have_attributes(trace_id: trace_id) }
      end

      context ':trace_flags' do
        let(:options) { { trace_flags: trace_flags } }
        let(:trace_flags) { 0x01 }

        it { is_expected.to have_attributes(trace_flags: 0x01) }
      end

      context ':trace_state' do
        let(:options) { { trace_state: trace_state } }
        let(:trace_state) { 'vendor1=value,v2=v' }

        it { is_expected.to have_attributes(trace_state: be_a_frozen_copy_of('vendor1=value,v2=v')) }
      end
    end
  end

  describe '#to_hash' do
    subject(:to_hash) { span_link.to_hash }

    context 'with required fields' do
      let(:options) { { span_id: 34, trace_id: 12 } }

      context 'when trace_id < 2^64' do
        it { is_expected.to eq(trace_id: 12, span_id: 34, flags: 0) }
      end

      context 'when trace_id >= 2^64' do
        let(:options) { { span_id: 34, trace_id: 2**64 + 12 } }
        it { is_expected.to eq(trace_id: 12, trace_id_high: 1, span_id: 34, flags: 0) }
      end
    end

    context 'with trace_state' do
      let(:options) { { span_id: 34, trace_id: 12, trace_state: 'dd=s:1' } }
      it { is_expected.to include(tracestate: 'dd=s:1') }
    end

    context 'with trace_flag' do
      context 'when trace_flag is unset' do
        let(:options) { { span_id: 34, trace_id: 12 } }
        it { is_expected.to include(flags: 0) }
      end

      context 'when trace_flags is 0' do
        let(:options) { { span_id: 34, trace_id: 12, trace_flags: 0 } }
        it { is_expected.to include(flags: 2147483648) }
      end

      context 'when trace_flag is 1' do
        let(:options) { { span_id: 34, trace_id: 12, trace_flags: 1 } }
        it { is_expected.to include(flags: 2147483649) }
      end
    end

    context 'with attributes' do
      let(:options) { { span_id: 34, trace_id: 12, attributes: { 'link.name' => :test_link, 'link.id' => 1 } } }
      it { is_expected.to include(attributes: { 'link.name' => 'test_link', 'link.id' => '1' }) }
    end
  end
end
