require 'spec_helper'

require 'datadog/core/encoding'
require 'datadog/tracing/transport/io/traces'

RSpec.describe Datadog::Tracing::Transport::IO::Traces::Response do
  context 'when implemented by a class' do
    subject(:response) { described_class.new(result, trace_count) }

    let(:result) { double('result') }
    let(:trace_count) { 2 }

    describe '#result' do
      subject(:get_result) { response.result }

      it { is_expected.to eq result }
    end

    describe '#trace_count' do
      subject(:get_trace_count) { response.trace_count }

      it { is_expected.to eq trace_count }
    end

    describe '#ok?' do
      subject(:ok?) { response.ok? }

      it { is_expected.to be true }
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::IO::Traces::Encoder do
  describe '#encode_data' do
    def compare_arrays(left = [], right = [])
      left.zip(right).each { |tuple| yield(*tuple) }
    end

    let(:trace_encoder) { Class.new { include Datadog::Tracing::Transport::IO::Traces::Encoder }.new }
    let(:encoder) { Datadog::Core::Encoding::JSONEncoder }

    describe '.encode_traces' do
      subject(:encode_traces) { trace_encoder.encode_traces(traces) }

      let(:traces) { get_test_traces(2) }

      it { is_expected.to be_a_kind_of(Hash) }

      describe 'produces a hash' do
        subject(:encoded) { encode_traces }

        it 'which is wrapped' do
          is_expected.to be_a_kind_of(Hash)
          is_expected.to include(:traces => kind_of(Array))
        end

        describe 'whose encoded traces' do
          subject(:encoded_traces) { encoded[:traces] }

          it 'contains the traces' do
            is_expected.to have(traces.length).items
          end

          it 'has IDs that are hex encoded' do
            compare_arrays(traces, encoded_traces) do |trace, encoded_trace|
              compare_arrays(trace.spans, encoded_trace) do |span, encoded_span|
                expect(encoded_span).to include(
                  :trace_id => span.trace_id.to_s(16),
                  :span_id => span.id.to_s(16),
                  :parent_id => span.parent_id.to_s(16)
                )
              end
            end
          end
        end
      end

      context 'when ID is missing' do
        subject(:encoded_traces) { encode_traces[:traces] }

        let(:missing_id) { :span_id }

        before do
          # Delete ID from each Span
          traces.each do |trace|
            trace.spans.each do |span|
              allow(span).to receive(:to_hash)
                .and_wrap_original do |m, *_args|
                  m.call.tap { |h| h.delete(missing_id) }
                end
            end
          end
        end

        it 'does not include the missing ID' do
          compare_arrays(traces, encoded_traces) do |trace, encoded_trace|
            compare_arrays(trace.spans, encoded_trace) do |_span, encoded_span|
              expect(encoded_span).to_not include(missing_id.to_s)
            end
          end
        end
      end
    end
  end
end
