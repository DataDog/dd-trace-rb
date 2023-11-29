# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/configuration/digest'
require 'datadog/core/remote/configuration/content'

RSpec.describe Datadog::Core::Remote::Configuration::Digest do
  let(:data) { StringIO.new('Hello World') }
  let(:content) do
    Datadog::Core::Remote::Configuration::Content.parse(
      {
        path: 'datadog/603646/ASM/exclusion_filters/config',
        content: data
      }
    )
  end

  describe '.hexdigest' do
    context 'valid type' do
      it 'returns hexdigest' do
        hexdigest = 'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e'
        expect(described_class.hexdigest(:sha256, data)).to eq(hexdigest)
      end

      it 'ensures data is rewinded' do
        expect(data.eof?).to eq(false)
        described_class.hexdigest(:sha256, data)
        expect(data.eof?).to eq(false)
      end
    end

    context 'invalid type is not supported' do
      it 'raises InvalidHashTypeError' do
        expect { described_class.hexdigest(:invalid, data) }.to raise_error(
          described_class::InvalidHashTypeError
        )
      end
    end
  end

  describe '#check' do
    let(:digest) { described_class.new(:sha256, Digest::SHA256.hexdigest(value)) }

    context 'valid content' do
      let(:value) { 'Hello World' }
      it 'returns true' do
        expect(digest.check(content)).to eq(true)
      end
    end

    context 'invalid content' do
      let(:value) { 'wrong value' }
      it 'returns false' do
        expect(digest.check(content)).to eq(false)
      end
    end
  end

  describe Datadog::Core::Remote::Configuration::DigestList do
    let(:digests) { { sha256: Digest::SHA256.hexdigest(value) } }
    subject(:digest_list) { described_class.parse(digests) }

    describe '#check' do
      context 'valid content' do
        let(:value) { 'Hello World' }
        it 'returns true' do
          expect(digest_list.check(content)).to eq(true)
        end
      end

      context 'invalid content' do
        let(:value) { 'wrong value' }
        it 'returns false' do
          expect(digest_list.check(content)).to eq(false)
        end
      end
    end
  end
end
