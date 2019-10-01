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
