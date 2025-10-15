# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'ostruct'

# Mock Karafka classes for testing DSM integration without requiring the gem
module Karafka
  module Messages
    class Messages
      def initialize(messages_array)
        @messages_array = messages_array
      end

      def each(&block)
        @messages_array.each(&block)
      end

      def count
        @messages_array.count
      end

      def first
        @messages_array.first
      end
    end
  end
end

# Mock message structure for Karafka DSM testing
def create_mock_message(topic: 'test_topic', partition: 0, offset: 100, headers: {})
  OpenStruct.new(
    topic: topic,
    metadata: OpenStruct.new(
      partition: partition,
      offset: offset,
      headers: headers,
      raw_headers: headers
    )
  )
end

require 'datadog'
require 'datadog/tracing/contrib/karafka/integration'
require 'datadog/tracing/contrib/karafka/patcher'

RSpec.describe 'Karafka Data Streams Integration' do
  let(:mock_ddsketch_instance) { double('DDSketchInstance', add: true, encode: 'encoded_data') }
  let(:mock_ddsketch) { double('DDSketch', supported?: true, new: mock_ddsketch_instance) }

  before do
    # Patch Messages class
    Karafka::Messages::Messages.prepend(Datadog::Tracing::Contrib::Karafka::MessagesPatch)

    Datadog.configure do |c|
      c.tracing.instrument :karafka
      c.tracing.data_streams.enabled = true
    end

    # Replace the processor with a real one using mock DDSketch
    allow(Datadog.configuration.tracing.data_streams).to receive(:processor).and_return(
      Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
    )
  end

  after do
    processor = Datadog.configuration.tracing.data_streams.processor
    processor.stop(true, 1) if processor&.enabled
  end

  describe 'message consumption with pathway context extraction' do
    it 'extracts pathway context from message headers and creates consume checkpoint' do
      processor = Datadog.configuration.tracing.data_streams.processor

      # Producer creates pathway context
      carrier = {}
      processor.set_produce_checkpoint('kafka', 'orders') do |key, value|
        carrier[key] = value
      end
      produce_hash = processor.pathway_context.hash

      # Create Karafka message with the pathway context in headers
      messages = Karafka::Messages::Messages.new([
        create_mock_message(
          topic: 'orders',
          partition: 0,
          offset: 100,
          headers: carrier
        )
      ])

      # Process the message - this should extract context and create consume checkpoint
      consumer_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor).and_return(consumer_processor)

      messages.each { |message| message }

      # Verify the consumer processor received and applied the pathway context
      # The hash should be different from produce hash (consume checkpoint)
      expect(consumer_processor.pathway_context.hash).not_to eq(produce_hash)
      expect(consumer_processor.pathway_context.hash).to be > 0

      consumer_processor.stop(true, 1)
    end

    it 'creates new pathway context when headers are missing' do
      processor = Datadog.configuration.tracing.data_streams.processor

      messages = Karafka::Messages::Messages.new([
        create_mock_message(
          topic: 'orders',
          partition: 0,
          offset: 100,
          headers: {}
        )
      ])

      initial_hash = processor.pathway_context.hash
      messages.each { |message| message }

      # Should create a new consume checkpoint even without carrier
      expect(processor.pathway_context.hash).not_to eq(initial_hash)
      expect(processor.pathway_context.hash).to be > 0
    end

    it 'processes multiple messages in batch' do
      processor = Datadog.configuration.tracing.data_streams.processor

      messages = Karafka::Messages::Messages.new([
        create_mock_message(topic: 'orders', partition: 0, offset: 100),
        create_mock_message(topic: 'orders', partition: 0, offset: 101),
        create_mock_message(topic: 'orders', partition: 0, offset: 102)
      ])

      expect { messages.each { |message| message } }.not_to raise_error

      # Each message should create a checkpoint
      expect(processor.pathway_context.hash).to be > 0
    end

    it 'skips DSM when disabled' do
      Datadog.configure do |c|
        c.tracing.data_streams.enabled = false
      end

      processor = Datadog.configuration.tracing.data_streams.processor
      initial_hash = processor.pathway_context.hash if processor

      messages = Karafka::Messages::Messages.new([
        create_mock_message(topic: 'orders', partition: 0, offset: 100)
      ])

      messages.each { |message| message }

      # Pathway context should not change when DSM is disabled
      expect(processor&.pathway_context&.hash).to eq(initial_hash) if processor
    end
  end

  describe 'end-to-end pathway propagation' do
    it 'propagates pathway context from producer to consumer through headers' do
      # Producer side: create checkpoint and inject into headers
      producer_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      headers = {}
      producer_processor.set_produce_checkpoint('kafka', 'orders') do |key, value|
        headers[key] = value
      end
      produce_hash = producer_processor.pathway_context.hash

      # Verify headers contain the propagation key
      expect(headers).to have_key(Datadog::Tracing::DataStreams::Processor::PROPAGATION_KEY)
      expect(headers[Datadog::Tracing::DataStreams::Processor::PROPAGATION_KEY]).not_to be_empty

      # Consumer side: process message with headers
      consumer_processor = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor).and_return(consumer_processor)

      messages = Karafka::Messages::Messages.new([
        create_mock_message(topic: 'orders', partition: 0, offset: 100, headers: headers)
      ])

      messages.each { |message| message }

      # Consumer should have different hash (consume checkpoint computed from produce hash)
      consume_hash = consumer_processor.pathway_context.hash
      expect(consume_hash).not_to eq(produce_hash)
      expect(consume_hash).to be > 0

      producer_processor.stop(true, 1)
      consumer_processor.stop(true, 1)
    end

    it 'maintains pathway continuity across multiple services' do
      # Service A produces
      service_a = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      headers_a = {}
      service_a.set_produce_checkpoint('kafka', 'topic-a') do |key, value|
        headers_a[key] = value
      end
      hash_a = service_a.pathway_context.hash

      # Service B consumes and produces
      service_b = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor).and_return(service_b)

      messages = Karafka::Messages::Messages.new([
        create_mock_message(topic: 'topic-a', partition: 0, offset: 100, headers: headers_a)
      ])
      messages.each { |message| message }

      hash_b_consume = service_b.pathway_context.hash

      headers_b = {}
      service_b.set_produce_checkpoint('kafka', 'topic-b') do |key, value|
        headers_b[key] = value
      end
      hash_b_produce = service_b.pathway_context.hash

      # Service C consumes
      service_c = Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: mock_ddsketch)
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor).and_return(service_c)

      messages_c = Karafka::Messages::Messages.new([
        create_mock_message(topic: 'topic-b', partition: 0, offset: 200, headers: headers_b)
      ])
      messages_c.each { |message| message }

      hash_c = service_c.pathway_context.hash

      # All hashes should be different (pathway progression through services)
      expect(hash_a).not_to eq(hash_b_consume)
      expect(hash_b_consume).not_to eq(hash_b_produce)
      expect(hash_b_produce).not_to eq(hash_c)

      service_a.stop(true, 1)
      service_b.stop(true, 1)
      service_c.stop(true, 1)
    end
  end
end
