# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe 'Datadog::Tracing::DataStreams::Processor checkpoints' do
  let(:mock_ddsketch_instance) { double('DDSketchInstance', add: true, encode: 'encoded_data') }
  let(:mock_ddsketch) { double('DDSketch', supported?: true, new: mock_ddsketch_instance) }
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch) }

  describe '#set_produce_checkpoint' do
    let(:type) { 'kafka' }
    let(:target) { 'orders' }

    it 'returns base64 encoded pathway context' do
      result = processor.set_produce_checkpoint(type, target)

      expect(result).to be_a(String)
      expect(result).not_to be_empty

      # Should be decodable
      decoded = processor.send(:decode_pathway_context, result)
      expect(decoded).not_to be_nil
      expect(decoded.hash).not_to eq(0)
    end

    it 'advances the pathway context with new hash' do
      initial_hash = processor.send(:get_current_context).hash

      processor.set_produce_checkpoint(type, target)

      new_context = processor.send(:get_current_context)
      expect(new_context.hash).not_to eq(initial_hash)
    end

    it 'includes correct tags in checkpoint' do
      allow(processor).to receive(:record_checkpoint_stats)

      processor.set_produce_checkpoint(type, target)

      expect(processor).to have_received(:record_checkpoint_stats) do |**kwargs|
        tags = kwargs[:tags]
        expect(tags).to include("type:#{type}")
        expect(tags).to include("topic:#{target}")
        expect(tags).to include('direction:out')
      end
    end

    it 'includes manual_checkpoint tag when requested' do
      allow(processor).to receive(:record_checkpoint_stats)

      processor.set_produce_checkpoint(type, target, manual_checkpoint: true)

      expect(processor).to have_received(:record_checkpoint_stats) do |**kwargs|
        expect(kwargs[:tags]).to include('manual_checkpoint:true')
      end
    end

    it 'yields pathway context to block for carrier injection' do
      injected_context = nil

      processor.set_produce_checkpoint(type, target) do |key, value|
        expect(key).to eq('dd-pathway-ctx-base64')
        injected_context = value
      end

      expect(injected_context).not_to be_nil
      expect(injected_context).to be_a(String)
    end

    it 'returns nil when processor is disabled' do
      processor.enabled = false

      result = processor.set_produce_checkpoint(type, target)

      expect(result).to be_nil
    end

    it 'tags active span with pathway hash' do
      span = instance_double(Datadog::Tracing::SpanOperation)
      allow(Datadog::Tracing).to receive(:active_span).and_return(span)
      allow(span).to receive(:set_tag)

      processor.set_produce_checkpoint(type, target)

      expect(span).to have_received(:set_tag).with('pathway.hash', kind_of(String))
    end

    it 'works with different topic names' do
      topics = ['orders', 'payments', 'user-events', 'notifications']

      topics.each do |topic|
        expect { processor.set_produce_checkpoint(type, topic) }.not_to raise_error

        result = processor.set_produce_checkpoint(type, topic)
        expect(result).to be_a(String)
        expect(processor.send(:decode_pathway_context, result)).not_to be_nil
      end
    end

    it 'restarts pathway on consecutive same-direction checkpoints (loop detection)' do
      # First produce checkpoint establishes pathway
      processor.set_produce_checkpoint(type, 'step1')
      context_after_first = processor.send(:get_current_context)
      first_pathway_start = context_after_first.pathway_start_sec

      # Second produce checkpoint (same direction) triggers loop detection and restarts pathway
      processor.set_produce_checkpoint(type, 'step2')
      context_after_second = processor.send(:get_current_context)

      # Pathway should have restarted (new pathway_start_sec)
      expect(context_after_second.pathway_start_sec).not_to eq(first_pathway_start)
      expect(context_after_second.pathway_start_sec).to be >= first_pathway_start
    end

    it 'calculates edge latency' do
      allow(processor).to receive(:record_checkpoint_stats)

      processor.set_produce_checkpoint(type, target)

      expect(processor).to have_received(:record_checkpoint_stats) do |**kwargs|
        expect(kwargs[:edge_latency_sec]).to be >= 0
      end
    end
  end

  describe '#set_consume_checkpoint' do
    let(:type) { 'kafka' }
    let(:source) { 'orders' }

    it 'returns base64 encoded pathway context' do
      result = processor.set_consume_checkpoint(type, source)

      expect(result).to be_a(String)
      expect(result).not_to be_empty

      decoded = processor.send(:decode_pathway_context, result)
      expect(decoded).not_to be_nil
    end

    it 'includes correct tags in checkpoint' do
      allow(processor).to receive(:record_checkpoint_stats)

      processor.set_consume_checkpoint(type, source)

      expect(processor).to have_received(:record_checkpoint_stats) do |**kwargs|
        tags = kwargs[:tags]
        expect(tags).to include("type:#{type}")
        expect(tags).to include("topic:#{source}")
        expect(tags).to include('direction:in')
      end
    end

    it 'includes manual_checkpoint tag by default' do
      allow(processor).to receive(:record_checkpoint_stats)

      processor.set_consume_checkpoint(type, source)

      expect(processor).to have_received(:record_checkpoint_stats) do |**kwargs|
        expect(kwargs[:tags]).to include('manual_checkpoint:true')
      end
    end

    it 'decodes pathway context from carrier when block provided' do
      # Setup: Create a produce checkpoint to get encoded context
      encoded_context = processor.set_produce_checkpoint(type, 'source-topic')

      # Carrier with encoded context
      carrier = { 'dd-pathway-ctx-base64' => encoded_context }

      # Act: Consume checkpoint extracts context from carrier
      processor.set_consume_checkpoint(type, source) { |key| carrier[key] }

      # Assert: Should have decoded and set the context
      current_context = processor.send(:get_current_context)
      expect(current_context.hash).not_to eq(0)
    end

    it 'returns nil when processor is disabled' do
      processor.enabled = false

      result = processor.set_consume_checkpoint(type, source)

      expect(result).to be_nil
    end

    it 'tags active span with pathway hash' do
      span = instance_double(Datadog::Tracing::SpanOperation)
      allow(Datadog::Tracing).to receive(:active_span).and_return(span)
      allow(span).to receive(:set_tag)

      processor.set_consume_checkpoint(type, source)

      expect(span).to have_received(:set_tag).with('pathway.hash', kind_of(String))
    end

    it 'handles missing pathway context in carrier gracefully' do
      # Empty carrier
      carrier = {}

      expect do
        processor.set_consume_checkpoint(type, source) { |key| carrier[key] }
      end.not_to raise_error
    end
  end

  describe 'produce-consume pathway flow' do
    let(:type) { 'kafka' }

    it 'maintains pathway continuity through produce and consume' do
      # Produce checkpoint
      produce_context = processor.set_produce_checkpoint(type, 'orders')
      produce_hash = processor.send(:get_current_context).hash
      produce_pathway_start = processor.send(:get_current_context).pathway_start_sec

      # Simulate message passing through carrier
      carrier = { 'dd-pathway-ctx-base64' => produce_context }

      # Consume checkpoint with context from carrier
      processor.set_consume_checkpoint(type, 'orders') { |key| carrier[key] }
      consume_hash = processor.send(:get_current_context).hash

      # Hashes should be different (new edge) but pathway start should be preserved
      expect(consume_hash).not_to eq(produce_hash)
      consume_pathway_start = processor.send(:get_current_context).pathway_start_sec
      expect(consume_pathway_start).to eq(produce_pathway_start)
    end

    it 'creates different hashes for different topics' do
      processor.set_produce_checkpoint(type, 'orders')
      context1 = processor.send(:get_current_context).hash

      # Reset processor state
      processor.instance_variable_set(:@pathway_context, Datadog::Tracing::DataStreams::PathwayContext.new(0, Time.now.to_f, Time.now.to_f))

      processor.set_produce_checkpoint(type, 'payments')
      context2 = processor.send(:get_current_context).hash

      expect(context1).not_to eq(context2)
    end
  end
end
