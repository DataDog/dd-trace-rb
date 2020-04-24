require 'spec_helper'
require 'spec/support/language_helpers'

require 'ddtrace/encoding'

RSpec.describe Datadog::Encoding do
  let(:obj) { [{ "foo" => 'bar' }] }

  context 'Msgpack encoding' do
    let(:encoder) { Datadog::Encoding::MsgpackEncoder }
    subject(:deserialized) { MessagePack.unpack(encoded) }

    context '#content_type' do
      it { expect(encoder.content_type).to eq('application/msgpack') }
    end

    context '#encode' do
      let(:encoded) { encoder.encode(obj) }

      it do
        is_expected.to eq(obj)
      end
    end

    context '#join' do
      let(:encoded) { encoder.join(elements) }
      let(:elements) { [encoder.encode(obj), encoder.encode(obj)] }

      it do
        is_expected.to eq([obj, obj])
      end
    end
  end

  context 'Msgpack encoding' do
    let(:encoder) { Datadog::Encoding::JSONEncoder }
    subject(:deserialized) { JSON.parse(encoded) }

    context '#content_type' do
      it { expect(encoder.content_type).to eq('application/json') }
    end

    context '#encode' do
      let(:encoded) { encoder.encode(obj) }

      it do
        is_expected.to eq(obj)
      end
    end

    context '#join' do
      let(:encoded) { encoder.join(elements) }
      let(:elements) { [encoder.encode(obj), encoder.encode(obj)] }

      it do
        is_expected.to eq([obj, obj])
      end
    end
  end
end

RSpec.describe Datadog::Encoding::JSONEncoder::V2 do
  def compare_arrays(left = [], right = [])
    left.zip(right).each { |tuple| yield(*tuple) }
  end

  describe '::encode_traces' do
    subject(:encode_traces) { described_class.encode_traces(traces) }
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
            compare_arrays(trace, encoded_trace) do |span, encoded_span|
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
          trace.each do |span|
            allow(span).to receive(:to_hash)
                             .and_wrap_original do |m, *_args|
              m.call.tap { |h| h.delete(missing_id) }
            end
          end
        end
      end

      it 'does not include the missing ID' do
        compare_arrays(traces, encoded_traces) do |trace, encoded_trace|
          compare_arrays(trace, encoded_trace) do |_span, encoded_span|
            expect(encoded_span).to_not include(missing_id.to_s)
          end
        end
      end
    end
  end
end
