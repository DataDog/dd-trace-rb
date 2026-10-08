# frozen_string_literal: true

require "datadog/data_streams/pathway_context"

RSpec.describe Datadog::DataStreams::PathwayContext do
  describe "encode/decode round-trip" do
    let(:hash_value) { 12345678901234567890 }
    let(:pathway_start) { Time.at(1609459200.123) } # 2021-01-01 00:00:00.123
    let(:current_edge_start) { Time.at(1609459260.456) } # 2021-01-01 00:01:00.456

    let(:context) do
      described_class.new(
        hash_value: hash_value,
        pathway_start: pathway_start,
        current_edge_start: current_edge_start
      )
    end

    it "successfully encodes and decodes pathway context" do
      # Arrange & Act: Encode to base64
      encoded = context.encode_b64

      # Act: Decode back to object
      decoded_context = described_class.decode_b64(encoded)

      # Assert: Values should match original
      expect(decoded_context).not_to be_nil
      expect(decoded_context.hash).to eq(hash_value)
      expect(decoded_context.pathway_start.to_f).to be_within(0.001).of(pathway_start.to_f)
      expect(decoded_context.current_edge_start.to_f).to be_within(0.001).of(current_edge_start.to_f)
    end

    it "handles edge cases in encoding/decoding" do
      # Test with zero values
      zero_context = described_class.new(hash_value: 0, pathway_start: Time.at(0), current_edge_start: Time.at(0))
      encoded = zero_context.encode_b64
      decoded = described_class.decode_b64(encoded)

      expect(decoded).not_to be_nil
      expect(decoded.hash).to eq(0)
      expect(decoded.pathway_start.to_f).to eq(0.0)
      expect(decoded.current_edge_start.to_f).to eq(0.0)
    end

    it "handles large values in encoding/decoding" do
      # Test with large values
      large_hash = 18446744073709551615 # Max uint64
      large_time = Time.now + 1000000 # Far future

      large_context = described_class.new(
        hash_value: large_hash,
        pathway_start: large_time,
        current_edge_start: large_time + 100
      )
      encoded = large_context.encode_b64
      decoded = described_class.decode_b64(encoded)

      expect(decoded).not_to be_nil
      expect(decoded.hash).to eq(large_hash)
      expect(decoded.pathway_start.to_f).to be_within(0.001).of(large_time.to_f)
      expect(decoded.current_edge_start.to_f).to be_within(0.001).of((large_time + 100).to_f)
    end
  end

  describe "decode error handling" do
    it "returns nil for invalid base64" do
      result = described_class.decode_b64("invalid-base64!")
      expect(result).to be_nil
    end

    it "returns nil for empty string" do
      result = described_class.decode_b64("")
      expect(result).to be_nil
    end

    it "returns nil for nil input" do
      result = described_class.decode_b64(nil)
      expect(result).to be_nil
    end

    it "returns nil for truncated data" do
      # Base64 encode only 4 bytes (need at least 8 for hash)
      truncated = Datadog::Core::Utils::Base64Codec.strict_encode64("\x01\x02\x03\x04")
      result = described_class.decode_b64(truncated)
      expect(result).to be_nil
    end
  end

  describe "VarInt encoding/decoding" do
    it "correctly encodes and decodes VarInt values" do
      test_values = [0, 1, 127, 128, 255, 256, 16383, 16384, 2097151, 2097152]

      test_values.each do |value|
        # Create context with test value as timestamp
        context = described_class.new(hash_value: 12345, pathway_start: Time.at(value / 1000.0), current_edge_start: Time.at(value / 1000.0))

        encoded = context.encode_b64
        decoded = described_class.decode_b64(encoded)

        expect(decoded).not_to be_nil, "Failed to decode VarInt value: #{value}"
        expect(decoded.pathway_start.to_f).to be_within(0.001).of(value / 1000.0)
        expect(decoded.current_edge_start.to_f).to be_within(0.001).of(value / 1000.0)
      end
    end
  end

  describe "cross-SDK wire compatibility with dd-trace-go" do
    # Regression test for https://github.com/DataDog/dd-trace-go/issues/5163: dd-trace-go's
    # internal/datastreams.Encode/Decode ZigZag-map the two pathway timestamps (reusing
    # sketches-go's signed varint helper), but this file previously used plain unsigned
    # LEB128, so any dd-trace-go consumer would silently decode the wrong timestamp for
    # every message produced by this gem.
    #
    # This fixture is the real base64 output of dd-trace-go v2.9.0's own
    # `Pathway{hash: 424242, pathwayStart: time.UnixMilli(1786000000123),
    # edgeStart: time.UnixMilli(1786000005456)}.EncodeBase64()` -- generated and verified
    # against the actual (unmodified) dd-trace-go source, not reimplemented here.
    let(:go_encoded_fixture) { "MnkGAAAAAAD2kare+meg5are+mc=" }

    it "decodes a real dd-trace-go-encoded pathway to the correct timestamps" do
      decoded = described_class.decode_b64(go_encoded_fixture)

      expect(decoded).not_to be_nil
      expect(decoded.hash).to eq(424242)
      expect((decoded.pathway_start.to_f * 1000).round).to eq(1786000000123)
      expect((decoded.current_edge_start.to_f * 1000).round).to eq(1786000005456)
    end

    it "produces wire-identical output to dd-trace-go for the same input" do
      context = described_class.new(
        hash_value: 424242,
        pathway_start: Time.at(1786000000.123),
        current_edge_start: Time.at(1786000005.456)
      )

      expect(context.encode_b64).to eq(go_encoded_fixture)
    end
  end
end
