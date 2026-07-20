# frozen_string_literal: true

require 'spec_helper'

require 'set'
require 'digest'

require 'datadog/open_feature/hooks/span_enrichment_hook'

RSpec.describe Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Codec do
  subject(:codec) { described_class }

  it 'encodes the golden vector' do
    expect(codec.encode_delta_varint(Set[100, 108, 128, 130])).to eq('ZAgUAg==')
  end

  it 'encodes an empty set to an empty string (tag omitted)' do
    expect(codec.encode_delta_varint(Set[])).to eq('')
  end

  it 'dedupes and sorts before encoding (Set semantics, order-independent)' do
    expect(codec.encode_delta_varint(Set[130, 100, 128, 108, 100])).to eq('ZAgUAg==')
  end

  # Regression: a delta >= 0x80 produces a varint with a continuation byte (>= 0x80).
  # The byte buffer must be binary; a UTF-8 buffer would re-encode 0x88 as the 2-byte
  # sequence 0xC2 0x88, so serial 2312 (bytes 88 12) would corrupt to 296002 on decode.
  it 'encodes serial ids with continuation bytes (>= 0x80) as raw bytes' do
    encoded = codec.encode_delta_varint(Set[2312])
    expect(encoded).to eq('iBI=')
    expect(encoded.unpack1('m0').bytes).to eq([0x88, 0x12])
  end

  it 'round-trips serial ids whose deltas exceed 0x7F' do
    ids = [100, 2312, 296_002]
    encoded = codec.encode_delta_varint(Set.new(ids))
    bytes = encoded.unpack1('m0').bytes
    decoded = []
    prev = 0
    shift = 0
    acc = 0
    bytes.each do |byte|
      acc |= (byte & 0x7F) << shift
      if (byte & 0x80).zero?
        prev += acc
        decoded << prev
        acc = 0
        shift = 0
      else
        shift += 7
      end
    end
    expect(decoded).to eq(ids)
  end

  it 'round-trips through delta decode' do
    encoded = codec.encode_delta_varint(Set[100, 108, 128, 130])
    bytes = encoded.unpack1('m0').bytes
    # Decode ULEB128 deltas and reconstruct the absolute ids.
    ids = []
    prev = 0
    shift = 0
    acc = 0
    bytes.each do |byte|
      acc |= (byte & 0x7F) << shift
      if (byte & 0x80).zero?
        prev += acc
        ids << prev
        acc = 0
        shift = 0
      else
        shift += 7
      end
    end
    expect(ids).to eq([100, 108, 128, 130])
  end

  it 'hashes the targeting key as lowercase hex SHA256' do
    expect(codec.hash_targeting_key('user-123'))
      .to eq('fcdec6df4d44dbc637c7c5b58efface52a7f8a88535423430255be0bb89bedd8')
  end
end
