require 'spec_helper'
require 'support/object_helpers'

require 'datadog/tracing/span_link'
require 'datadog/tracing/trace_digest'

RSpec.describe Datadog::Tracing::SpanLink do
  subject(:span_link) { described_class.new(attributes: attributes, digest: digest) }

  let(:attributes) { nil }
  let(:digest) do
    Datadog::Tracing::TraceDigest.new(
      span_id: span_id,
      trace_id: trace_id,
      trace_flags: trace_flags,
      trace_state: trace_state,
    )
  end
  let(:span_id) { nil }
  let(:trace_id) { nil }
  let(:trace_state) { nil }
  let(:trace_flags) { nil }

  describe '::new' do
    context 'by default' do
      let(:digest) { nil }
      let(:attributes) { nil }

      it do
        is_expected.to have_attributes(
          span_id: nil,
          attributes: {},
          trace_id: nil,
          trace_flags: nil,
          trace_state: nil,
        )
      end
    end

    context 'given' do
      context ':attributes' do
        let(:attributes) { { tag: 'value' } }
        it { is_expected.to have_attributes(attributes: attributes) }
      end

      context ':digest with' do
        context ':span_id' do
          let(:span_id) { Datadog::Tracing::Utils.next_id }
          it { is_expected.to have_attributes(span_id: span_id) }
        end

        context ':trace_id' do
          let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }
          it { is_expected.to have_attributes(trace_id: trace_id) }
        end

        context ':trace_flags' do
          let(:trace_flags) { 0x01 }
          it { is_expected.to have_attributes(trace_flags: 0x01) }
        end

        context ':trace_state' do
          let(:trace_state) { 'vendor1=value,v2=v' }
          it { is_expected.to have_attributes(trace_state: 'vendor1=value,v2=v') }
        end
      end
    end
  end

  describe '#to_hash' do
    subject(:to_hash) { span_link.to_hash }
    let(:span_id) { 34 }
    let(:trace_id) { 12 }

    context 'with required fields' do
      context 'when trace_id < 2^64' do
        it { is_expected.to eq(trace_id: 12, span_id: 34, flags: 0) }
      end

      context 'when trace_id >= 2^64' do
        let(:trace_id) { 2**64 + 12 }
        it { is_expected.to eq(trace_id: 12, trace_id_high: 1, span_id: 34, flags: 0) }
      end
    end

    context 'when required fields are not set' do
      let(:span_id) { nil }
      let(:trace_id) { nil }
      it { is_expected.to eq(trace_id: 0, span_id: 0, flags: 0) }
    end

    context 'when trace_state is set' do
      let(:trace_state) { 'dd=s:1' }
      it { is_expected.to include(tracestate: 'dd=s:1') }
    end

    context 'when trace_flag is set' do
      context 'when trace_flag is unset' do
        it { is_expected.to include(flags: 0) }
      end

      context 'when trace_flags is 0' do
        let(:trace_flags) { 0 }
        it { is_expected.to include(flags: 2147483648) }
      end

      context 'when trace_flag is 1' do
        let(:trace_flags) { 1 }
        it { is_expected.to include(flags: 2147483649) }
      end
    end

    context 'when attributes is set' do
      let(:attributes) { { 'link.name' => :test_link, 'link.id' => 1, 'nested' => [true, [2, 3], 'val'] } }
      it {
        is_expected.to include(
          attributes: { 'link.name' => 'test_link', 'link.id' => '1', 'nested.0' => 'true',
                        'nested.1.0' => '2', 'nested.1.1' => '3', 'nested.2' => 'val', }
        )
      }
    end
  end
end
