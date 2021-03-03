require 'spec_helper'
require 'spec/support/language_helpers'

require 'ddtrace/encoding'

RSpec.describe Datadog::Encoding do
  let(:obj) { [{ 'foo' => 'bar' }] }

  context 'Msgpack encoding' do
    let(:encoder) { Datadog::Encoding::MsgpackEncoder }

    subject(:deserialized) { MessagePack.unpack(encoded) }

    describe '#content_type' do
      it { expect(encoder.content_type).to eq('application/msgpack') }
    end

    describe '#encode' do
      let(:encoded) { encoder.encode(obj) }

      it do
        is_expected.to eq(obj)
      end
    end

    describe '#join' do
      let(:encoded) { encoder.join(elements) }
      let(:elements) { [encoder.encode(obj), encoder.encode(obj)] }

      it do
        is_expected.to eq([obj, obj])
      end
    end
  end

  context 'JSON encoding' do
    let(:encoder) { Datadog::Encoding::JSONEncoder }

    subject(:deserialized) { JSON.parse(encoded) }

    describe '#content_type' do
      it { expect(encoder.content_type).to eq('application/json') }
    end

    describe '#encode' do
      let(:encoded) { encoder.encode(obj) }

      it do
        is_expected.to eq(obj)
      end
    end

    describe '#join' do
      let(:encoded) { encoder.join(elements) }
      let(:elements) { [encoder.encode(obj), encoder.encode(obj)] }

      it do
        is_expected.to eq([obj, obj])
      end
    end
  end
end
