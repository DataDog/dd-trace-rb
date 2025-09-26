# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe 'Datadog::Tracing::DataStreams::Processor#set_checkpoint' do
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new }

  describe '#set_checkpoint' do
    let(:tags) { ['topic:orders'] }
    let(:now_sec) { 1609459200.123 }
    let(:payload_size) { 1024 }

    before do
      # Set up initial pathway context
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(
        12345, # initial hash
        1609459100.0,            # pathway start: 100 seconds ago
        1609459150.0             # current edge start: 50 seconds ago
      )
      processor.instance_variable_set(:@pathway_context, initial_context)
    end

    it 'advances the pathway context with new hash and edge start time' do
      # Arrange: Initial context set in before block

      # Act: Create checkpoint
      result = processor.set_checkpoint(tags, now_sec, payload_size)

      # Assert: Context should be advanced
      new_context = processor.get_current_pathway
      expect(new_context.hash).not_to eq(12345) # Hash should change
      expect(new_context.pathway_start_sec).to eq(1609459100.0) # Pathway start unchanged
      expect(new_context.current_edge_start_sec).to eq(now_sec) # Edge start advances
    end

    it 'returns base64 encoded pathway context' do
      # Act
      result = processor.set_checkpoint(tags, now_sec, payload_size)

      # Assert: Should return valid base64 encoded context
      expect(result).to be_a(String)
      expect(result).not_to be_empty

      # Should be decodable
      decoded = processor.decode_pathway_context(result)
      expect(decoded).not_to be_nil
      expect(decoded.current_edge_start_sec).to eq(now_sec)
    end

    it 'computes new hash from current hash and tags' do
      # Arrange: Get original hash
      original_hash = processor.get_current_pathway.hash

      # Act: Create checkpoint with specific tags
      processor.set_checkpoint(['topic:orders'], now_sec)
      hash1 = processor.get_current_pathway.hash

      # Reset and try different tags
      processor.set_pathway_context(
        Datadog::Tracing::DataStreams::PathwayContext.new(
          original_hash,
          1609459100.0,
          1609459150.0
        )
      )
      processor.set_checkpoint(['topic:users'], now_sec)
      hash2 = processor.get_current_pathway.hash

      # Assert: Different tags should produce different hashes
      expect(hash1).not_to eq(original_hash)
      expect(hash2).not_to eq(original_hash)
      expect(hash1).not_to eq(hash2)
    end

    it 'uses current time when now_sec is not provided' do
      # Arrange: Don't provide timestamp
      before_time = Time.now.to_f

      # Act
      processor.set_checkpoint(tags)

      # Assert: Should use current time (approximately)
      new_context = processor.get_current_pathway
      expect(new_context.current_edge_start_sec).to be >= before_time
      expect(new_context.current_edge_start_sec).to be <= Time.now.to_f
    end

    it 'handles zero and negative latencies gracefully' do
      # Arrange: Set edge start time to current time (zero latency)
      current_context = Datadog::Tracing::DataStreams::PathwayContext.new(12345, 1609459100.0, now_sec)
      processor.set_pathway_context(current_context)

      # Act & Assert: Should not raise error
      expect { processor.set_checkpoint(tags, now_sec) }.not_to raise_error

      # Edge case: Future edge start time (negative latency)
      future_context = Datadog::Tracing::DataStreams::PathwayContext.new(12345, 1609459100.0, now_sec + 100)
      processor.set_pathway_context(future_context)

      expect { processor.set_checkpoint(tags, now_sec) }.not_to raise_error
    end

    it 'returns nil when processor is disabled' do
      # Arrange
      processor.enabled = false

      # Act
      result = processor.set_checkpoint(tags, now_sec, payload_size)

      # Assert
      expect(result).to be_nil
    end

    it 'preserves original pathway start time across multiple checkpoints' do
      # Arrange: Original pathway start time
      original_start = 1609459000.0
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(12345, original_start, 1609459100.0)
      processor.set_pathway_context(initial_context)

      # Act: Create multiple checkpoints
      processor.set_checkpoint(['topic:step1'], now_sec)
      processor.set_checkpoint(['topic:step2'], now_sec + 10)
      processor.set_checkpoint(['topic:step3'], now_sec + 20)

      # Assert: Pathway start should remain unchanged
      final_context = processor.get_current_pathway
      expect(final_context.pathway_start_sec).to eq(original_start)
    end

    it 'works with various tag formats' do
      # Test different tag formats that might be used
      tag_formats = [
        ['topic:orders'],
        ['service:payment', 'env:prod'],
        ['queue:high-priority'],
        [] # Empty tags
      ]

      tag_formats.each do |test_tags|
        # Should not raise errors with any tag format
        expect { processor.set_checkpoint(test_tags, now_sec) }.not_to raise_error

        # Should produce a valid encoded result
        result = processor.set_checkpoint(test_tags, now_sec)
        expect(result).to be_a(String)
        expect(processor.decode_pathway_context(result)).not_to be_nil
      end
    end
  end

  describe 'checkpoint stats recording' do
    let(:tags) { ['topic:orders'] }
    let(:now_sec) { 1609459200.123 }

    before do
      # Set up pathway with known edge start time for latency calculation
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(12345, 1609459100.0, 1609459150.0)
      processor.set_pathway_context(initial_context)
    end

    it 'calculates edge latency correctly' do
      # Arrange: Edge started at 1609459150.0, checkpoint at 1609459200.123
      expected_latency = 1609459200.123 - 1609459150.0 # 50.123 seconds

      # Mock the stats recording to capture the latency
      allow(processor).to receive(:record_checkpoint_stats) do |**kwargs|
        expect(kwargs[:edge_latency_sec]).to be_within(0.001).of(expected_latency)
      end

      # Act
      processor.set_checkpoint(tags, now_sec)
    end

    it 'passes correct parameters to stats recording' do
      # Arrange: Set up mocks to verify stats recording
      original_hash = processor.get_current_pathway.hash

      expect(processor).to receive(:record_checkpoint_stats) do |**kwargs|
        expect(kwargs[:parent_hash]).to eq(original_hash)
        expect(kwargs[:tags]).to eq(tags)
        expect(kwargs[:timestamp_sec]).to eq(now_sec)
        expect(kwargs[:payload_size]).to eq(1024)
        expect(kwargs[:hash]).not_to eq(original_hash) # Should be new hash
        expect(kwargs[:edge_latency_sec]).to be > 0
      end

      # Act
      processor.set_checkpoint(tags, now_sec, 1024)
    end
  end
end

