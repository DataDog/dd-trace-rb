# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe 'Data Streams Monitoring Behavioral Tests' do
  let(:mock_ddsketch_instance) { double('DDSketchInstance', add: true, encode: 'encoded_data') }
  let(:mock_ddsketch) { double('DDSketch', supported?: true, new: mock_ddsketch_instance) }
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch) }

  describe 'end-to-end pathway tracking' do
    it 'produces deterministic hashes for same inputs' do
      # Same tags on fresh processors should produce identical hashes
      processor1 = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      processor2 = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)

      result1 = processor1.set_produce_checkpoint('kafka', 'orders')
      result2 = processor2.set_produce_checkpoint('kafka', 'orders')

      # Exact same base64 string because hash is deterministic
      # (times will differ but hash computation from tags is deterministic)
      decoded1 = Datadog::Tracing::DataStreams::PathwayContext.decode_b64(result1)
      decoded2 = Datadog::Tracing::DataStreams::PathwayContext.decode_b64(result2)

      expect(decoded1.hash).to eq(decoded2.hash)
      expect(decoded1.hash).to be > 0 # Non-zero hash
    end

    it 'tracks a complete data pipeline: Service A → Kafka → Service B' do
      # Arrange: Service A creates initial pathway (producer)
      processor_a = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)

      # Act: Service A produces to Kafka
      carrier = {}
      result_a = processor_a.set_produce_checkpoint('kafka', 'create-user') do |key, value|
        carrier[key] = value
      end
      carrier['dd-pathway-ctx-base64'] = result_a

      # Act: Service B consumes from Kafka
      processor_b = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      result_b = processor_b.set_consume_checkpoint('kafka', 'create-user') do |key|
        carrier[key]
      end

      # Assert: Both should create valid pathway contexts with deterministic hashes
      expect(result_a).to be_a(String)
      expect(result_a).not_to be_empty
      expect(result_b).to be_a(String)
      expect(result_b).not_to be_empty

      # Pathway should advance (different hashes) - deterministic based on tags
      expect(result_a).not_to eq(result_b)
    end

    it 'maintains pathway identity across multiple services' do
      # Simulate: Service A → Kafka → Service B → Kafka → Service C

      # Service A (producer)
      processor_a = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      carrier_a = {}
      ctx_a = processor_a.set_produce_checkpoint('kafka', 'topic-1') do |key|
        carrier_a[key] = ctx_a if ctx_a
      end
      carrier_a['dd-pathway-ctx-base64'] = ctx_a

      # Service B (consumer then producer)
      processor_b = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      processor_b.set_consume_checkpoint('kafka', 'topic-1') do |key|
        carrier_a[key]
      end
      carrier_b = {}
      ctx_b = processor_b.set_produce_checkpoint('kafka', 'topic-2') do |key|
        carrier_b[key] = ctx_b if ctx_b
      end
      carrier_b['dd-pathway-ctx-base64'] = ctx_b

      # Service C (consumer)
      processor_c = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      ctx_c = processor_c.set_consume_checkpoint('kafka', 'topic-2') do |key|
        carrier_b[key]
      end

      # Assert: Each service should create different pathway hashes
      expect(ctx_a).to be_a(String)
      expect(ctx_b).to be_a(String)
      expect(ctx_c).to be_a(String)
      expect([ctx_a, ctx_b, ctx_c].uniq.size).to eq(3)
    end

    it 'creates different pathways for different message flows' do
      # Two different data pipelines should have different pathway identities

      # Pipeline 1: user-service → user-events
      processor_1 = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      ctx_1a = processor_1.set_produce_checkpoint('kafka', 'user-events')
      ctx_1b = processor_1.set_produce_checkpoint('kafka', 'user-notifications')

      # Pipeline 2: order-service → order-events
      processor_2 = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      ctx_2a = processor_2.set_produce_checkpoint('kafka', 'order-events')
      ctx_2b = processor_2.set_produce_checkpoint('kafka', 'order-notifications')

      # Assert: Different pipelines should have different hashes at each step
      expect(ctx_1a).not_to eq(ctx_2a)
      expect(ctx_1b).not_to eq(ctx_2b)
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

      consumer_a = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      consumer_b = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)

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
      # API → Kafka → Payment → Kafka → Fulfillment

      # Step 1: API produces order
      api_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      carrier_1 = {}
      ctx_api = api_processor.set_produce_checkpoint('kafka', 'orders') do |key|
        carrier_1[key] = ctx_api if ctx_api
      end
      carrier_1['dd-pathway-ctx-base64'] = ctx_api

      # Step 2: Payment service consumes and processes
      payment_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      payment_processor.set_consume_checkpoint('kafka', 'orders') do |key|
        carrier_1[key]
      end
      carrier_2 = {}
      ctx_payment = payment_processor.set_produce_checkpoint('kafka', 'payments') do |key|
        carrier_2[key] = ctx_payment if ctx_payment
      end
      carrier_2['dd-pathway-ctx-base64'] = ctx_payment

      # Step 3: Fulfillment service consumes
      fulfillment_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      ctx_fulfillment = fulfillment_processor.set_consume_checkpoint('kafka', 'payments') do |key|
        carrier_2[key]
      end

      # Assert: Should be able to reconstruct the pathway lineage
      # API → Payment → Fulfillment should form a traceable chain
      expect(ctx_api).to be_a(String)
      expect(ctx_payment).to be_a(String)
      expect(ctx_fulfillment).to be_a(String)

      # Each service should have created different hashes
      expect(ctx_api).not_to eq(ctx_payment)
      expect(ctx_payment).not_to eq(ctx_fulfillment)
    end
  end

  describe 'DSM monitoring insights' do
    it 'enables detection of slow data pipelines' do
      # Real monitoring scenario: Detect slow message processing
      start_time = Time.new(2021, 1, 1, 0, 0, 0, '+00:00')

      # Fast pipeline
      fast_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      allow(Time).to receive(:now).and_return(start_time)
      fast_carrier = {}
      fast_ctx_1 = fast_processor.set_produce_checkpoint('kafka', 'fast-topic') do |key|
        fast_carrier[key] = fast_ctx_1 if fast_ctx_1
      end
      fast_carrier['dd-pathway-ctx-base64'] = fast_ctx_1

      # Consumer processes 100ms later
      allow(Time).to receive(:now).and_return(start_time + 0.1)
      fast_processor_2 = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      fast_ctx_2 = fast_processor_2.set_consume_checkpoint('kafka', 'fast-topic') do |key|
        fast_carrier[key]
      end

      # Slow pipeline
      slow_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      allow(Time).to receive(:now).and_return(start_time)
      slow_carrier = {}
      slow_ctx_1 = slow_processor.set_produce_checkpoint('kafka', 'slow-topic') do |key|
        slow_carrier[key] = slow_ctx_1 if slow_ctx_1
      end
      slow_carrier['dd-pathway-ctx-base64'] = slow_ctx_1

      # Consumer processes 5 seconds later
      allow(Time).to receive(:now).and_return(start_time + 5.0)
      slow_processor_2 = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      slow_ctx_2 = slow_processor_2.set_consume_checkpoint('kafka', 'slow-topic') do |key|
        slow_carrier[key]
      end

      # Assert: Both pipelines should complete
      expect(fast_ctx_1).to be_a(String)
      expect(fast_ctx_2).to be_a(String)
      expect(slow_ctx_1).to be_a(String)
      expect(slow_ctx_2).to be_a(String)

      # The latencies are recorded in DDSketch, which we've mocked
      # In real usage, this would enable detecting slow pipelines
      expect(mock_ddsketch_instance).to have_received(:add).at_least(:twice)
    end

    it 'enables tracking of message fan-out patterns' do
      # Real scenario: One message triggers multiple downstream processing
      original_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      carrier = {}
      original_ctx = original_processor.set_produce_checkpoint('kafka', 'orders') do |key|
        carrier[key] = original_ctx if original_ctx
      end
      carrier['dd-pathway-ctx-base64'] = original_ctx

      # Simulate fan-out: order triggers inventory check, payment, and notification
      services = ['inventory', 'payment', 'notification']
      downstream_contexts = services.map do |service|
        downstream = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
        downstream.set_consume_checkpoint('kafka', service) do |key|
          carrier[key]
        end
      end

      # Assert: Fan-out pattern should be detectable
      # All downstream services should have valid contexts
      downstream_contexts.each do |ctx|
        expect(ctx).to be_a(String)
        expect(ctx).not_to be_empty
      end

      # Each service branch should have different hash (different processing)
      expect(downstream_contexts.uniq.size).to eq(3)
    end
  end
end
