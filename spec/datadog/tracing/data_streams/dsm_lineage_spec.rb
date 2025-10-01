# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe 'Data Streams Monitoring Pathway Lineage' do
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new }

  describe 'parent-child pathway relationships' do
    it 'tracks parent hash when advancing pathways' do
      # Arrange: Get initial hash
      initial_hash = processor.get_current_pathway.hash

      # Act: Create checkpoint (should become parent)
      processor.set_checkpoint(['service:api'])
      api_context = processor.get_current_pathway

      # Act: Create another checkpoint
      processor.set_checkpoint(['topic:orders'])
      orders_context = processor.get_current_pathway

      # Assert: Parent-child relationships should be trackable
      expect(api_context.parent_hash).to eq(initial_hash) # API's parent is initial
      expect(orders_context.parent_hash).to eq(api_context.hash) # Orders' parent is API

      # This creates lineage: initial → API → orders
      expect(orders_context.hash).not_to eq(api_context.hash) # Advanced
      expect(api_context.hash).not_to eq(initial_hash) # Advanced
    end

    it 'preserves parent lineage across service boundaries' do
      # Arrange: Service A creates pathway
      processor.set_checkpoint(['service:user-api'])
      api_hash = processor.get_current_pathway.hash
      encoded_context = processor.encode_pathway_context

      # Act: Service B receives and continues pathway
      processor_b = Datadog::Tracing::DataStreams::Processor.new
      processor_b.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => encoded_context })
      inherited_context = processor_b.get_current_pathway

      processor_b.set_checkpoint(['service:payment'])
      payment_context = processor_b.get_current_pathway

      # Assert: Lineage should be maintained across services
      expect(inherited_context.hash).to eq(api_hash)                    # Inherited API's hash
      expect(payment_context.parent_hash).to eq(api_hash)               # Payment's parent is API
      expect(payment_context.hash).not_to eq(api_hash)                  # Payment advanced

      # This enables reconstruction: user-api → payment
    end

    it 'enables detection of pathway convergence and fan-out' do
      # Real scenario: Multiple sources converge, then fan out again

      # Sources: user-service and admin-service both feed into validation
      user_processor = Datadog::Tracing::DataStreams::Processor.new
      admin_processor = Datadog::Tracing::DataStreams::Processor.new

      user_processor.set_checkpoint(['source:user-service'])
      admin_processor.set_checkpoint(['source:admin-service'])

      user_hash = user_processor.get_current_pathway.hash
      admin_hash = admin_processor.get_current_pathway.hash

      # Convergence: Both feed into validation service (separate processors)
      user_to_validation = Datadog::Tracing::DataStreams::Processor.new
      admin_to_validation = Datadog::Tracing::DataStreams::Processor.new

      user_to_validation.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => user_processor.encode_pathway_context })
      admin_to_validation.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => admin_processor.encode_pathway_context })

      user_to_validation.set_checkpoint(['service:validation'])
      admin_to_validation.set_checkpoint(['service:validation'])

      user_validation_hash = user_to_validation.get_current_pathway.hash
      admin_validation_hash = admin_to_validation.get_current_pathway.hash

      # Assert: Can track convergence patterns
      expect(user_to_validation.get_current_pathway.parent_hash).to eq(user_hash)   # User → Validation lineage
      expect(admin_to_validation.get_current_pathway.parent_hash).to eq(admin_hash) # Admin → Validation lineage
      expect(user_validation_hash).not_to eq(admin_validation_hash) # Different pathways through validation

      # This enables detecting: 2 sources → 1 service (with different pathway identities)
    end
  end

  describe 'real monitoring use cases' do
    it 'enables tracking message processing latency end-to-end' do
      # Real use case: Measure how long messages take to flow through system
      start_time = 1609459200.0

      # Arrange: Set up producer with known start time
      producer_processor = Datadog::Tracing::DataStreams::Processor.new
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      producer_processor.set_pathway_context(initial_context)

      # Producer creates checkpoint
      producer_checkpoint = producer_processor.set_checkpoint(['service:order-producer'], start_time)
      producer_context = producer_processor.get_current_pathway

      # Consumer receives message and processes it
      consumer_processor = Datadog::Tracing::DataStreams::Processor.new
      consumer_processor.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => producer_checkpoint })
      consumer_received_context = consumer_processor.get_current_pathway

      consumer_processor.set_checkpoint(['service:order-consumer'], start_time + 7)
      consumer_final_context = consumer_processor.get_current_pathway

      # Assert: Can measure processing latencies
      producer_processing_time = producer_context.current_edge_start_sec - producer_context.pathway_start_sec
      consumer_processing_time = consumer_final_context.current_edge_start_sec - consumer_received_context.current_edge_start_sec
      end_to_end_time = consumer_final_context.current_edge_start_sec - producer_context.pathway_start_sec

      expect(producer_processing_time).to eq(0.0) # Producer was instant
      expect(consumer_processing_time).to eq(7.0) # Consumer took 7 seconds
      expect(end_to_end_time).to eq(7.0)          # End-to-end pipeline time

      # Parent relationship enables tracing: producer → consumer
      expect(consumer_final_context.parent_hash).to eq(consumer_received_context.hash)
    end

    it 'enables detection of stuck or looping messages' do
      # Real monitoring case: Detect when messages loop or get stuck

      # Message flows: service-a → service-b → service-a (loop!)
      start_time = 1609459200.0

      processor.set_checkpoint(['service:a'], start_time)
      service_a_hash = processor.get_current_pathway.hash
      encoded_a = processor.encode_pathway_context

      # Message goes to Service B
      processor_b = Datadog::Tracing::DataStreams::Processor.new
      processor_b.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => encoded_a })
      processor_b.set_checkpoint(['service:b'], start_time + 1)
      service_b_hash = processor_b.get_current_pathway.hash
      encoded_b = processor_b.encode_pathway_context

      # Message goes back to Service A (potential loop)
      processor_a_again = Datadog::Tracing::DataStreams::Processor.new
      processor_a_again.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => encoded_b })
      processor_a_again.set_checkpoint(['service:a'], start_time + 2) # Same service tag as before!

      # Assert: Can detect potential looping by analyzing pathway lineage
      final_context = processor_a_again.get_current_pathway

      # Lineage should show: initial → A → B → A
      # This pattern (returning to same service) could indicate a loop
      expect(final_context.parent_hash).to eq(service_b_hash) # Current parent is B
      expect(processor_b.get_current_pathway.parent_hash).to eq(service_a_hash) # B's parent was A

      # The pathway should still advance (not create infinite loop)
      expect(final_context.hash).not_to eq(service_a_hash) # A's second checkpoint ≠ A's first
      expect(final_context.hash).not_to eq(service_b_hash) # A's second ≠ B
    end
  end
end
