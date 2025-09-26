# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe 'Data Streams Monitoring Behavioral Tests' do
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new }

  describe 'end-to-end pathway tracking' do
    it 'tracks a complete data pipeline: Service A → Kafka → Service B' do
      # Arrange: Service A creates initial pathway (producer)
      service_a_tags = ['service:user-service', 'topic:create-user', 'direction:out']
      service_a_initial_hash = processor.get_current_pathway.hash

      # Act: Service A creates checkpoint (becomes parent)
      checkpoint_a = processor.set_checkpoint(service_a_tags)
      service_a_final_hash = processor.get_current_pathway.hash

      # Act: Service B receives message and continues pathway (consumer)
      processor_b = Datadog::Tracing::DataStreams::Processor.new
      processor_b.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => checkpoint_a })
      service_b_received_hash = processor_b.get_current_pathway.hash

      service_b_tags = ['service:notification-service', 'topic:send-email', 'direction:in']
      checkpoint_b = processor_b.set_checkpoint(service_b_tags)
      service_b_final_hash = processor_b.get_current_pathway.hash

      # Assert: Pathway lineage should be trackable
      expect(service_a_final_hash).not_to eq(service_a_initial_hash) # Service A advanced
      expect(service_b_received_hash).to eq(service_a_final_hash)    # Service B inherited A's hash
      expect(service_b_final_hash).not_to eq(service_b_received_hash) # Service B advanced

      # This creates a trackable chain: initial → A → B
      expect([service_a_initial_hash, service_a_final_hash, service_b_final_hash].uniq.size).to eq(3)
    end

    it 'maintains pathway identity across multiple services' do
      # Simulate: Service A → Kafka → Service B → Kafka → Service C

      # Service A (producer)
      processor_a = Datadog::Tracing::DataStreams::Processor.new
      processor_a.set_checkpoint(['service:api', 'direction:out'])
      context_after_a = processor_a.get_current_pathway

      # Message travels to Service B (consumer)
      processor_b = Datadog::Tracing::DataStreams::Processor.new
      processor_b.set_pathway_context(context_after_a)
      processor_b.set_checkpoint(['service:processor', 'direction:in'])
      context_after_b = processor_b.get_current_pathway

      # Message travels to Service C (producer)
      processor_c = Datadog::Tracing::DataStreams::Processor.new
      processor_c.set_pathway_context(context_after_b)
      processor_c.set_checkpoint(['service:analytics', 'direction:out'])
      context_after_c = processor_c.get_current_pathway

      # Assert: Pathway start time changes as time moves forward
      expect(context_after_a.pathway_start_sec).to be <= context_after_b.pathway_start_sec
      expect(context_after_b.pathway_start_sec).to be <= context_after_c.pathway_start_sec

      # Each service should create a new checkpoint with different tags
      # The hash should advance through the pathway as each service processes the message
      expect(context_after_a.hash).not_to eq(context_after_b.hash)
      expect(context_after_b.hash).not_to eq(context_after_c.hash)
    end

    it 'creates different pathways for different message flows' do
      # Two different data pipelines should have different pathway identities

      # Pipeline 1: user-service → user-events
      processor.set_checkpoint(['service:user-service'])
      pipeline1_step1 = processor.get_current_pathway
      processor.set_checkpoint(['topic:user-events'])
      pipeline1_step2 = processor.get_current_pathway

      # Pipeline 2: order-service → order-events
      processor_2 = Datadog::Tracing::DataStreams::Processor.new
      processor_2.set_checkpoint(['service:order-service'])
      pipeline2_step1 = processor_2.get_current_pathway
      processor_2.set_checkpoint(['topic:order-events'])
      pipeline2_step2 = processor_2.get_current_pathway

      # Assert: Different pipelines should have different hashes at each step
      expect(pipeline1_step1.hash).not_to eq(pipeline2_step1.hash)
      expect(pipeline1_step2.hash).not_to eq(pipeline2_step2.hash)
    end
  end

  describe 'real-world Kafka consumer scenarios' do
    it 'tracks consumer progress through topic partitions' do
      # Simulate consuming messages from a Kafka topic over time
      topic = 'user-events'
      partition = 0
      base_time = 1609459200.0

      # Act: Consumer processes messages sequentially
      offsets = [100, 101, 102, 103, 104]
      offsets.each_with_index do |offset, i|
        processor.track_kafka_consume(topic, partition, offset, base_time + i)
      end

      # Assert: Should be able to detect consumer progress
      # (This will be more meaningful once we implement actual stats collection)
      expect { processor.track_kafka_consume(topic, partition, 105, base_time + 5) }.not_to raise_error
    end

    it 'detects consumer lag when offsets have gaps' do
      # Real scenario: Consumer falls behind and misses messages
      topic = 'orders'
      partition = 0
      base_time = 1609459200.0

      # Act: Simulate lagging consumer (gaps in offsets)
      processor.track_kafka_consume(topic, partition, 100, base_time)
      processor.track_kafka_consume(topic, partition, 105, base_time + 1) # Gap: missed 101-104
      processor.track_kafka_consume(topic, partition, 110, base_time + 2) # Gap: missed 106-109

      # Assert: System should handle lag gracefully
      expect { processor.track_kafka_consume(topic, partition, 115, base_time + 3) }.not_to raise_error
    end

    it 'handles multiple consumers on same topic/partition' do
      # Scenario: Consumer group rebalancing or multiple consumers
      topic = 'events'
      partition = 0
      base_time = 1609459200.0

      consumer_a = Datadog::Tracing::DataStreams::Processor.new
      consumer_b = Datadog::Tracing::DataStreams::Processor.new

      # Act: Two consumers process different ranges of offsets
      consumer_a.track_kafka_consume(topic, partition, 100, base_time)
      consumer_b.track_kafka_consume(topic, partition, 101, base_time + 1)
      consumer_a.track_kafka_consume(topic, partition, 102, base_time + 2)

      # Assert: Both consumers should work independently
      expect { consumer_a.track_kafka_consume(topic, partition, 103, base_time + 3) }.not_to raise_error
      expect { consumer_b.track_kafka_consume(topic, partition, 104, base_time + 4) }.not_to raise_error
    end
  end

  describe 'pathway context evolution' do
    it 'shows how pathway context changes through a real message flow' do
      # Real scenario: Order processing pipeline
      start_time = Time.now.to_f

      # Step 1: API receives order (producer)
      api_checkpoint = processor.set_checkpoint(['service:api', 'operation:create-order', 'direction:out'], start_time)
      api_context = processor.get_current_pathway

      # Step 2: Message goes to Kafka, Payment service picks it up (consumer)
      payment_processor = Datadog::Tracing::DataStreams::Processor.new
      payment_processor.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => api_checkpoint })
      payment_checkpoint = payment_processor.set_checkpoint(['service:payment', 'operation:charge-card', 'direction:in'], start_time + 1)
      payment_context = payment_processor.get_current_pathway

      # Step 3: Message goes to Kafka, Fulfillment service picks it up (producer)
      fulfillment_processor = Datadog::Tracing::DataStreams::Processor.new
      fulfillment_processor.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => payment_checkpoint })
      fulfillment_checkpoint = fulfillment_processor.set_checkpoint(
        ['service:fulfillment', 'operation:ship-order', 'direction:out'],
        start_time + 2
      )
      fulfillment_context = fulfillment_processor.get_current_pathway

      # Assert: Should be able to reconstruct the pathway lineage
      # API → Payment → Fulfillment should form a traceable chain
      # Pathway start time changes as time moves forward
      expect(api_context.pathway_start_sec).to be <= payment_context.pathway_start_sec
      expect(payment_context.pathway_start_sec).to be <= fulfillment_context.pathway_start_sec

      # Each service should have created a parent-child relationship:
      # - Payment's "parent" should be API's final hash
      # - Fulfillment's "parent" should be Payment's final hash
      # This enables reconstructing: API → Payment → Fulfillment
      expect(api_context.hash).not_to eq(payment_context.hash) # API created new pathway
      expect(payment_context.hash).not_to eq(fulfillment_context.hash) # Payment created new pathway

      # Edge times should track processing steps
      expect(payment_context.current_edge_start_sec).to be_within(0.01).of(start_time + 1)
      expect(fulfillment_context.current_edge_start_sec).to be_within(0.01).of(start_time + 2)
    end
  end

  describe 'DSM monitoring insights' do
    it 'enables detection of slow data pipelines' do
      # Real monitoring scenario: Detect slow message processing
      start_time = 1609459200.0

      # Fast pipeline: Set up with known start time
      fast_processor = Datadog::Tracing::DataStreams::Processor.new
      fast_initial = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      fast_processor.set_pathway_context(fast_initial)
      fast_processor.set_checkpoint(['service:fast-service'], start_time)
      fast_processor.set_checkpoint(['service:consumer'], start_time + 0.1) # 100ms later
      fast_context = fast_processor.get_current_pathway

      # Slow pipeline: Set up with known start time
      slow_processor = Datadog::Tracing::DataStreams::Processor.new
      slow_initial = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      slow_processor.set_pathway_context(slow_initial)
      slow_processor.set_checkpoint(['service:slow-service'], start_time)
      slow_processor.set_checkpoint(['service:consumer'], start_time + 5.0) # 5 seconds later
      slow_context = slow_processor.get_current_pathway

      # Assert: Should be able to distinguish fast vs slow pipelines
      fast_total_time = fast_context.current_edge_start_sec - start_time
      slow_total_time = slow_context.current_edge_start_sec - start_time

      expect(slow_total_time).to be > fast_total_time
      expect(slow_total_time).to be_within(0.01).of(5.0)    # Slow pipeline took 5 seconds
      expect(fast_total_time).to be_within(0.01).of(0.1)    # Fast pipeline took 0.1 seconds
    end

    it 'enables tracking of message fan-out patterns' do
      # Real scenario: One message triggers multiple downstream processing
      original_checkpoint = processor.set_checkpoint(['service:order-api'], Time.now.to_f)

      # Simulate fan-out: order triggers inventory check, payment, and notification
      services = ['inventory', 'payment', 'notification']
      downstream_processors = services.map do |service|
        downstream = Datadog::Tracing::DataStreams::Processor.new
        downstream.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => original_checkpoint })
        downstream.set_checkpoint(["service:#{service}"])
        downstream
      end

      # Assert: Fan-out pattern should be detectable
      original_start = processor.get_current_pathway.pathway_start_sec
      original_hash_after_checkpoint = processor.get_current_pathway.hash

      # All downstream services should inherit from the same parent
      downstream_processors.each do |downstream|
        downstream_context = downstream.get_current_pathway
        # Should share same pathway origin (fan-out from single source)
        expect(downstream_context.pathway_start_sec).to be_within(0.01).of(original_start)

        # Each service branch should have different hash (different processing)
        expect(downstream_context.hash).not_to eq(original_hash_after_checkpoint)
      end

      # All branches should have different final hashes (different services)
      final_hashes = downstream_processors.map { |p| p.get_current_pathway.hash }
      expect(final_hashes.uniq.size).to eq(3) # All branches unique

      # This enables detecting: 1 source → 3 different processing paths
    end
  end
end
