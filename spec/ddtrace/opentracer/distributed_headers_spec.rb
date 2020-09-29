require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::DistributedHeaders do
    include_context 'OpenTracing helpers'

    subject(:headers) { described_class.new(carrier) }
    let(:carrier) { instance_double(Datadog::OpenTracer::Carrier) }

    describe '#valid?' do
      subject(:valid) { headers.valid? }

      before(:each) do
        allow(carrier).to receive(:[])
          .with(described_class::HTTP_HEADER_TRACE_ID)
          .and_return(trace_id)

        allow(carrier).to receive(:[])
          .with(described_class::HTTP_HEADER_PARENT_ID)
          .and_return(parent_id)
      end

      context 'when #trace_id is missing' do
        let(:trace_id) { nil }
        let(:parent_id) { (Datadog::Span::EXTERNAL_MAX_ID + 1).to_s }
        it { is_expected.to be false }
      end

      context 'when #parent_id is missing' do
        let(:trace_id) { (Datadog::Span::EXTERNAL_MAX_ID + 1).to_s }
        let(:parent_id) { nil }
        it { is_expected.to be false }
      end

      context 'when both #trace_id and #parent_id are present' do
        let(:trace_id) { (Datadog::Span::EXTERNAL_MAX_ID - 1).to_s }
        let(:parent_id) { (Datadog::Span::EXTERNAL_MAX_ID - 1).to_s }
        it { is_expected.to be true }
      end
    end

    describe '#trace_id' do
      subject(:trace_id) { headers.trace_id }

      before(:each) do
        allow(carrier).to receive(:[])
          .with(described_class::HTTP_HEADER_TRACE_ID)
          .and_return(value)
      end

      context 'when the header is missing' do
        let(:value) { nil }
      end

      context 'when the header is present' do
        context 'but the value is out of range' do
          let(:value) { (Datadog::Span::EXTERNAL_MAX_ID + 1).to_s }
          it { is_expected.to be nil }
        end

        context 'and the value is in range' do
          let(:value) { (Datadog::Span::EXTERNAL_MAX_ID - 1).to_s }
          it { is_expected.to eq value.to_i }

          context 'as a negative signed integer' do
            # Convert signed int to unsigned int.
            let(:value) { -8809075535603237910.to_s }
            it { is_expected.to eq 9637668538106313706 }
          end
        end
      end
    end

    describe '#parent_id' do
      subject(:trace_id) { headers.parent_id }

      before(:each) do
        allow(carrier).to receive(:[])
          .with(described_class::HTTP_HEADER_PARENT_ID)
          .and_return(value)
      end

      context 'when the header is missing' do
        let(:value) { nil }
      end

      context 'when the header is present' do
        context 'but the value is out of range' do
          let(:value) { (Datadog::Span::EXTERNAL_MAX_ID + 1).to_s }
          it { is_expected.to be nil }
        end

        context 'and the value is in range' do
          let(:value) { (Datadog::Span::EXTERNAL_MAX_ID - 1).to_s }
          it { is_expected.to eq value.to_i }

          context 'as a negative signed integer' do
            # Convert signed int to unsigned int.
            let(:value) { -8809075535603237910.to_s }
            it { is_expected.to eq 9637668538106313706 }
          end
        end
      end
    end

    describe '#sampling_priority' do
      subject(:trace_id) { headers.sampling_priority }

      before(:each) do
        allow(carrier).to receive(:[])
          .with(described_class::HTTP_HEADER_SAMPLING_PRIORITY)
          .and_return(value)
      end

      context 'when the header is missing' do
        let(:value) { nil }
      end

      context 'when the header is present' do
        context 'but the value is out of range' do
          let(:value) { '-1' }
          it { is_expected.to be nil }
        end

        context 'and the value is in range' do
          let(:value) { '1' }
          it { is_expected.to eq value.to_i }
        end
      end
    end
  end
end
