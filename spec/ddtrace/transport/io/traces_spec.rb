require 'spec_helper'

require 'datadog/core/encoding'
require 'ddtrace/transport/io/traces'

RSpec.describe Datadog::Transport::IO::Traces::Response do
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

RSpec.describe Datadog::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }

  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }

  describe '#send_traces' do
    context 'given traces' do
      subject(:send_traces) { client.send_traces(traces) }

      let(:traces) { instance_double(Array) }
      let(:encoded_traces) { double('encoded traces') }
      let(:result) { double('IO result') }

      before do
        expect_any_instance_of(Datadog::Transport::IO::Traces::Parcel).to receive(:encode_with)
          .with(encoder)
          .and_return(encoded_traces)

        expect(client.out).to receive(:puts)
          .with(encoded_traces)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Transport::IO::Traces::Response))
      end

      it do
        is_expected.to all(be_a(Datadog::Transport::IO::Traces::Response))
        expect(send_traces.first.result).to eq(result)
      end
    end

    context 'given traces and a block' do
      subject(:send_traces) { client.send_traces(traces) { |out, data| target.write(out, data) } }

      let(:traces) { instance_double(Array) }
      let(:encoded_traces) { double('encoded traces') }
      let(:result) { double('IO result') }
      let(:target) { double('target') }

      before do
        expect_any_instance_of(Datadog::Transport::IO::Traces::Parcel).to receive(:encode_traces)
          .with(encoder, traces)
          .and_return(encoded_traces)

        expect(target).to receive(:write)
          .with(client.out, encoded_traces)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Transport::IO::Traces::Response))
      end

      it do
        is_expected.to all(be_a(Datadog::Transport::IO::Traces::Response))
        expect(send_traces.first.result).to eq(result)
      end
    end
  end
end

RSpec.describe Datadog::Transport::IO::Traces::Encoder do
  describe '#encode_data' do
    def compare_arrays(left = [], right = [])
      left.zip(right).each { |tuple| yield(*tuple) }
    end

    let(:trace_encoder) { Class.new { include Datadog::Transport::IO::Traces::Encoder }.new }
    let(:encoder) { Datadog::Core::Encoding::JSONEncoder }

    describe '.encode_traces' do
      subject(:encode_traces) { trace_encoder.encode_traces(encoder, traces) }

      let(:traces) { get_test_traces(2) }

      it { is_expected.to be_a_kind_of(String) }

      describe 'produces a JSON schema' do
        subject(:schema) { JSON.parse(encode_traces) }

        it 'which is wrapped' do
          is_expected.to be_a_kind_of(Hash)
          is_expected.to include('traces' => kind_of(Array))
        end

        describe 'whose encoded traces' do
          subject(:encoded_traces) { schema['traces'] }

          it 'contains the traces' do
            is_expected.to have(traces.length).items
          end

          it 'has IDs that are hex encoded' do
            compare_arrays(traces, encoded_traces) do |trace, encoded_trace|
              compare_arrays(trace.spans, encoded_trace) do |span, encoded_span|
                described_class::ENCODED_IDS.each do |id|
                  encoded_id = encoded_span[id.to_s].to_i(16)
                  original_id = span.send(id)
                  expect(encoded_id).to eq(original_id)
                end
              end
            end
          end
        end
      end

      context 'when ID is missing' do
        subject(:encoded_traces) { JSON.parse(encode_traces)['traces'] }

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
