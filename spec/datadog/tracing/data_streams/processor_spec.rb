# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe Datadog::Tracing::DataStreams::Processor do
  let(:processor) { described_class.new }

  describe '#decode_pathway_context' do
    it 'decodes valid pathway context' do
      # Arrange: Create and encode a pathway context
      original_context = Datadog::Tracing::DataStreams::PathwayContext.new(12345, 1609459200.123, 1609459260.456)
      encoded_ctx = original_context.encode_b64

      # Act: Decode using processor
      decoded_context = processor.decode_pathway_context(encoded_ctx)

      # Assert: Should return decoded PathwayContext
      expect(decoded_context).not_to be_nil
      expect(decoded_context.hash).to eq(12345)
      expect(decoded_context.pathway_start_sec).to be_within(0.001).of(1609459200.123)
      expect(decoded_context.current_edge_start_sec).to be_within(0.001).of(1609459260.456)
    end

    it 'returns nil for invalid context' do
      result = processor.decode_pathway_context('invalid-base64')
      expect(result).to be_nil
    end

    it 'returns nil when processor disabled' do
      processor.enabled = false

      original_context = Datadog::Tracing::DataStreams::PathwayContext.new(12345, 1609459200.123, 1609459260.456)
      encoded_ctx = original_context.encode_b64

      result = processor.decode_pathway_context(encoded_ctx)
      expect(result).to be_nil
    end
  end

  describe '#encode_pathway_context' do
    it 'encodes current pathway context' do
      result = processor.encode_pathway_context
      expect(result).to be_a(String)
      expect(result).not_to be_empty

      # Should be able to decode it back
      decoded = processor.decode_pathway_context(result)
      expect(decoded).not_to be_nil
    end

    it 'returns nil when processor disabled' do
      processor.enabled = false
      result = processor.encode_pathway_context
      expect(result).to be_nil
    end
  end

  describe '#decode_and_set_pathway_context' do
    let(:headers_with_context) do
      original_context = Datadog::Tracing::DataStreams::PathwayContext.new(54321, 1609459300.789, 1609459360.012)
      { 'dd-pathway-ctx-base64' => original_context.encode_b64 }
    end

    it 'decodes and sets pathway context from headers' do
      # Arrange: Get original pathway context for comparison
      original_encoded = headers_with_context['dd-pathway-ctx-base64']
      original_decoded = processor.decode_pathway_context(original_encoded)

      # Act: Decode and set from headers
      processor.decode_and_set_pathway_context(headers_with_context)

      # Assert: Current pathway should be updated
      current_pathway = processor.get_current_pathway
      expect(current_pathway).not_to be_nil
      expect(current_pathway.hash).to eq(original_decoded.hash)
      expect(current_pathway.pathway_start_sec).to eq(original_decoded.pathway_start_sec)
      expect(current_pathway.current_edge_start_sec).to eq(original_decoded.current_edge_start_sec)
    end

    it 'does nothing when no pathway context in headers' do
      original_pathway = processor.get_current_pathway

      processor.decode_and_set_pathway_context({})

      # Should remain unchanged
      expect(processor.get_current_pathway).to eq(original_pathway)
    end

    it 'does nothing when processor disabled' do
      processor.enabled = false
      original_pathway = processor.get_current_pathway

      processor.decode_and_set_pathway_context(headers_with_context)

      expect(processor.get_current_pathway).to eq(original_pathway)
    end
  end
end

