# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/core'
require 'datadog/core/ddsketch'
require 'ostruct'
require 'datadog/tracing/contrib/kafka/integration'
require 'datadog/tracing/contrib/kafka/instrumentation/producer'
require 'datadog/tracing/contrib/kafka/instrumentation/consumer'

RSpec.describe 'Kafka Data Streams instrumentation' do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :kafka, configuration_options
      c.data_streams.enabled = true
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:kafka].reset_configuration!
    example.run
    Datadog.registry[:kafka].reset_configuration!
  end

  describe 'pathway context' do
    before do
      skip_if_libdatadog_not_supported(self)
    end

    let(:test_producer_class) do
      Class.new do
        attr_accessor :pending_message_queue

        def initialize
          @pending_message_queue = []
        end

        def deliver_messages(**kwargs)
          # Mimic ruby-kafka behavior: operate on internal queue (no modification needed here)
          result = {delivered_count: @pending_message_queue.size}
          @pending_message_queue.clear
          result
        end

        prepend Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer
      end
    end

    let(:producer) { test_producer_class.new }
    let(:message) { OpenStruct.new(topic: 'test_topic', value: 'test_value', headers: {}) }

    it 'automatically injects pathway context when producing messages' do
      # Test that the instrumentation automatically injects DSM headers
      producer.pending_message_queue << message
      producer.deliver_messages

      # Verify the header was automatically set by instrumentation
      encoded_ctx = message.headers['dd-pathway-ctx-base64']
      expect(encoded_ctx).to be_a(String)
      expect(encoded_ctx).not_to be_empty

      # Decode and verify it's a valid pathway context
      decoded_ctx = Datadog::DataStreams::PathwayContext.decode_b64(encoded_ctx)
      expect(decoded_ctx).to be_a(Datadog::DataStreams::PathwayContext)
      expect(decoded_ctx.hash).to be > 0 # Should have a deterministic hash
      expect(decoded_ctx.pathway_start).not_to be_nil
      expect(decoded_ctx.pathway_start).to be_within(5).of(Time.now) # Should be recent
      expect(decoded_ctx.current_edge_start).not_to be_nil
      expect(decoded_ctx.current_edge_start).to be_within(5).of(Time.now) # Should be recent
    end
  end

  describe 'checkpointing' do
    before do
      skip_if_libdatadog_not_supported(self)
    end

    let(:test_producer_class) do
      Class.new do
        attr_accessor :pending_message_queue

        def initialize
          @pending_message_queue = []
        end

        def deliver_messages(**kwargs)
          result = {delivered_count: @pending_message_queue.size}
          @pending_message_queue.clear
          result
        end

        prepend Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer
      end
    end

    let(:test_consumer_class) do
      Class.new do
        attr_accessor :test_message

        def each_message(**kwargs)
          # Yield the test message set by the test
          yield(@test_message) if @test_message && block_given?
        end

        prepend Datadog::Tracing::Contrib::Kafka::Instrumentation::Consumer
      end
    end

    let(:consumer) { test_consumer_class.new }

    it 'automatically processes pathway context when consuming messages' do
      # Simulate a complete produce → consume flow to test auto-instrumentation
      processor = Datadog::DataStreams.send(:processor)

      # Step 1: Produce a message (instrumentation automatically adds pathway context)
      producer_message = OpenStruct.new(topic: 'test_topic', value: 'test', headers: {})
      test_producer = test_producer_class.new
      test_producer.pending_message_queue << producer_message
      test_producer.deliver_messages

      # Capture the producer pathway context
      producer_ctx_b64 = producer_message.headers['dd-pathway-ctx-base64']
      producer_ctx = Datadog::DataStreams::PathwayContext.decode_b64(producer_ctx_b64)

      # Step 2: Consume the message (instrumentation automatically processes pathway context)
      consumer_message = OpenStruct.new(
        topic: 'test_topic',
        partition: 0,
        offset: 100,
        headers: {'dd-pathway-ctx-base64' => producer_ctx_b64}
      )

      # Set the message for the consumer to yield
      consumer.test_message = consumer_message

      # Process the message - instrumentation should automatically call set_consume_checkpoint
      consumer.each_message do |msg|
        # By the time this block runs, the instrumentation has already:
        # 1. Extracted the pathway context from message headers
        # 2. Called set_consume_checkpoint
        # 3. Updated the processor's internal pathway context

        # Verify the message still has the producer's pathway context in headers
        expect(msg.headers['dd-pathway-ctx-base64']).to eq(producer_ctx_b64)
        expect(msg.topic).to eq('test_topic')

        # Verify the processor has updated its context after processing this message
        current_ctx = processor.instance_variable_get(:@pathway_context)
        expect(current_ctx).to be_a(Datadog::DataStreams::PathwayContext)
        expect(current_ctx.hash).to be > 0
        expect(current_ctx.hash).not_to eq(producer_ctx.hash) # Consumer hash should differ (direction:in vs direction:out)
        expect(current_ctx.pathway_start).to be_within(0.001).of(producer_ctx.pathway_start) # Should preserve pathway start time (within 1ms due to serialization precision loss)
      end
    end
  end

  describe 'when DSM is disabled' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :kafka
        c.data_streams.enabled = false
      end
    end

    let(:test_producer_class) do
      Class.new do
        attr_accessor :pending_message_queue

        def initialize
          @pending_message_queue = []
        end

        def deliver_messages(**kwargs)
          result = {delivered_count: @pending_message_queue.size}
          @pending_message_queue.clear
          result
        end

        prepend Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer
      end
    end

    let(:test_consumer_class) do
      Class.new do
        attr_accessor :test_message

        def each_message(**kwargs)
          yield(@test_message) if @test_message && block_given?
        end

        prepend Datadog::Tracing::Contrib::Kafka::Instrumentation::Consumer
      end
    end

    it 'producer does not inject DSM headers when disabled' do
      producer = test_producer_class.new
      message = OpenStruct.new(topic: 'test_topic', value: 'test', headers: {})

      producer.pending_message_queue << message
      producer.deliver_messages

      # Should not have added DSM header
      expect(message.headers).not_to include('dd-pathway-ctx-base64')
    end

    it 'consumer does not process DSM headers when disabled' do
      consumer = test_consumer_class.new
      message = OpenStruct.new(
        topic: 'test_topic',
        partition: 0,
        offset: 100,
        headers: {'dd-pathway-ctx-base64' => 'some-context'}
      )

      consumer.test_message = message

      # Should not raise error even though DSM is disabled
      expect {
        consumer.each_message { |msg| expect(msg).to eq(message) }
      }.not_to raise_error
    end
  end
end
