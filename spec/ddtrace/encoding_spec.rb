require 'spec_helper'
require 'spec/support/language_helpers'

require 'ddtrace/encoding'

RSpec.describe Datadog::Encoding do
  subject(:encode) { encoder.method(:encode_traces) }

  let(:block) { proc { block_response } }
  let(:block_response) { double('response') }

  context 'Base encoder' do
    let(:encoder) { Class.new { include Datadog::Encoding::Encoder }.new }

    let(:traces) { get_test_traces(3) }

    before do
      allow(encoder).to receive(:encode).with(traces[0].map(&:to_hash)).and_return('blob1')
      allow(encoder).to receive(:encode).with(traces[1].map(&:to_hash)).and_return('blob2')
      allow(encoder).to receive(:encode).with(traces[2].map(&:to_hash)).and_return('blob3')
      allow(encoder).to receive(:join) { |arr| arr.join(',') }
    end

    it do
      expect { |b| encode.call(traces, &b) }.to yield_with_args('blob1,blob2,blob3', 3)
    end

    it 'returns yielded block returns' do
      expect(encode.call(traces, &block)).to eq([block_response])
    end

    context 'with large batch of traces' do
      let(:max_size) { 10 }

      it do
        expect { |b| encode.call(traces, max_size: max_size, &b) }
          .to yield_successive_args(['blob1,blob2', 2], ['blob3', 1])
      end

      it 'returns yielded block returns' do
        expect(encode.call(traces, max_size: max_size, &block)).to eq([block_response, block_response])
      end
    end

    context 'with individual traces too large' do
      let(:max_size) { 4 }

      it do
        expect { |b| encode.call(traces, max_size: max_size, &b) }.not_to yield_control
      end
    end
  end

  context 'Msgpack encoding' do
    let(:encoder) { Datadog::Encoding::MsgpackEncoder }
    let(:traces) { get_test_traces(2) }

    it do
      expect(encode.call(traces) do |encoded, size|
        expect(size).to eq(2)

        items = MessagePack.unpack(encoded)
        expect(items.size).to eq(2)
        expect(items.first).to eq(traces.first.map(&:to_hash).map(&:stringify_keys))

        block_response
      end).to eq([block_response])
    end
  end

  context 'JSON encoding' do
    let(:encoder) { Datadog::Encoding::JSONEncoder }
    let(:traces) { get_test_traces(2) }

    it do
      expect(encode.call(traces) do |encoded, size|
        expect(size).to eq(2)

        items = JSON.parse(encoded)
        expect(items.size).to eq(2)
        expect(items.first).to eq(traces.first.map(&:to_hash).map(&:stringify_keys))

        block_response
      end).to eq([block_response])
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
