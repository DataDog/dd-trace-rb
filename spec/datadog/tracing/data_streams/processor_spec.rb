# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe Datadog::Tracing::DataStreams::Processor do
  let(:mock_ddsketch_instance) { double('DDSketchInstance', add: true, encode: 'encoded_data') }
  let(:mock_ddsketch) { double('DDSketch', supported?: true, new: mock_ddsketch_instance) }
  let(:processor) { described_class.new(ddsketch_class: mock_ddsketch) }

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

  describe 'periodic flushing' do
    let(:mock_transport) { double('transport') }
    let(:processor) { described_class.new(ddsketch_class: mock_ddsketch, interval: 0.1) } # Fast interval for testing

    before do
      allow(processor).to receive(:send_stats_to_agent).and_return(true)
      allow(processor).to receive(:hostname).and_return('test-host')
    end

    after { processor.stop(true, 1) }

    describe '#initialize' do
      it 'sets up periodic worker with default interval' do
        processor = described_class.new(ddsketch_class: mock_ddsketch)
        expect(processor.loop_base_interval).to eq(10.0)
      end

      it 'sets up periodic worker with custom interval' do
        processor = described_class.new(ddsketch_class: mock_ddsketch, interval: 5.0)
        expect(processor.loop_base_interval).to eq(5.0)
      end

      it 'uses environment variable for interval' do
        allow(ENV).to receive(:fetch).with('_DD_TRACE_STATS_WRITER_INTERVAL', '10.0').and_return('15.0')
        processor = described_class.new(ddsketch_class: mock_ddsketch)
        expect(processor.loop_base_interval).to eq(15.0)
      end
    end

    describe '#perform' do
      it 'does nothing when processor is disabled' do
        processor.enabled = false
        expect(processor).not_to receive(:send_stats_to_agent)
        processor.perform
      end

      it 'does nothing when no data to send' do
        expect(processor).not_to receive(:send_stats_to_agent)
        processor.perform
      end

      it 'sends stats when data is available' do
        # Add some test data
        processor.set_checkpoint(['topic:test-topic', 'partition:0'], Time.now.to_f, 100)

        expect(processor).to receive(:send_stats_to_agent).with(hash_including(
          'Service' => Datadog.configuration.service,
          'TracerVersion' => Datadog::VERSION::STRING,
          'Lang' => 'ruby',
          'Hostname' => 'test-host'
        ))

        processor.perform
      end

      it 'handles errors gracefully' do
        processor.set_checkpoint(['topic:test-topic', 'partition:0'], Time.now.to_f, 100)
        allow(processor).to receive(:send_stats_to_agent).and_raise(StandardError, 'Network error')

        expect { processor.perform }.not_to raise_error
      end
    end

    describe 'worker lifecycle' do
      it 'can be started and stopped' do
        expect(processor).to respond_to(:start)
        expect(processor).to respond_to(:stop)
        expect(processor).to respond_to(:running?)
      end

      it 'inherits from Core::Worker' do
        expect(processor).to be_a(Datadog::Core::Worker)
      end

      it 'includes Workers::Polling' do
        expect(processor.class.ancestors).to include(Datadog::Core::Workers::Polling)
      end
    end
  end
end

