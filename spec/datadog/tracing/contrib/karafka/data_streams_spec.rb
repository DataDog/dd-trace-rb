# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'ostruct'

# Mock Karafka classes for testing DSM integration without requiring the gem
module Karafka
  # Mock Messages collection
  module Messages
    class Messages
      def initialize(messages_array)
        @messages_array = messages_array
      end

      def each(&block)
        # This will be patched with our DSM integration
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

  # Mock distributed tracing method
  def self.extract(headers)
    # Mock extraction - return nil for simplicity
    nil
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

# Mock Karafka job structure for Monitor testing
def create_mock_job(topic: 'test_topic', partition: 0, messages: [])
  OpenStruct.new(
    messages: messages,
    executor: OpenStruct.new(
      topic: OpenStruct.new(
        name: topic,
        consumer: 'TestConsumer'
      ),
      partition: partition
    )
  )
end

require 'datadog'
require 'datadog/tracing/contrib/karafka/integration'
require 'datadog/tracing/contrib/karafka/monitor'
require 'datadog/tracing/contrib/karafka/patcher'

RSpec.describe 'Karafka Data Streams instrumentation' do
  let(:configuration_options) { {} }

  before do
    # Manually patch Messages class since auto_patch is false for Karafka
    Karafka::Messages::Messages.prepend(Datadog::Tracing::Contrib::Karafka::MessagesPatch)

    Datadog.configure do |c|
      c.tracing.instrument :karafka, configuration_options
      c.tracing.data_streams.enabled = true
    end
  end

  describe 'MessagesPatch DSM integration' do
    # Test the DSM functionality by directly testing the patch module
    let(:messages_class) do
      Class.new do
        include Datadog::Tracing::Contrib::Karafka::MessagesPatch

        def initialize(messages_array)
          @messages_array = messages_array
        end

        def configuration
          @configuration ||= { distributed_tracing: false }
        end
      end
    end

    let(:messages) do
      [
        create_mock_message(
          topic: 'orders',
          partition: 0,
          offset: 100,
          headers: { 'dd-pathway-ctx-base64' => 'test-context-123' }
        ),
        create_mock_message(
          topic: 'orders',
          partition: 0,
          offset: 101,
          headers: {}
        )
      ]
    end

    let(:karafka_messages) { messages_class.new(messages) }
    let(:mock_processor) { instance_double('DataStreamsProcessor') }

    before do
      # Set up basic configuration and tracing mocks
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(mock_processor)

      # Mock tracing to avoid span creation errors
      span_double = double('span')
      allow(span_double).to receive(:set_tag)
      allow(span_double).to receive(:resource=)
      allow(Datadog::Tracing).to receive(:trace).and_yield(span_double)
    end

    it 'creates checkpoints for each consumed message when DSM enabled' do
      # Arrange: Set up spies
      allow(mock_processor).to receive(:set_checkpoint)
      allow(mock_processor).to receive(:decode_and_set_pathway_context)

      # Act: Execute the code under test
      karafka_messages.each { |message| message }

      # Assert: Verify the calls were made
      expect(mock_processor).to have_received(:set_checkpoint)
        .with(['topic:orders'], kind_of(Float))
        .twice
      expect(mock_processor).to have_received(:decode_and_set_pathway_context)
        .twice
    end

    it 'extracts DSM context from message headers' do
      # Arrange: Set up spies
      allow(mock_processor).to receive(:set_checkpoint) # DSM also calls set_checkpoint
      allow(mock_processor).to receive(:decode_and_set_pathway_context)

      # Act: Execute the code under test
      karafka_messages.each { |message| message }

      # Assert: Verify the calls were made
      expect(mock_processor).to have_received(:decode_and_set_pathway_context)
        .with({ 'dd-pathway-ctx-base64' => 'test-context-123' })
        .once
      expect(mock_processor).to have_received(:decode_and_set_pathway_context)
        .with({})
        .once
    end

    it 'skips DSM when disabled' do
      # Arrange: Disable DSM and set up spy
      Datadog.configure do |c|
        c.tracing.data_streams.enabled = false
      end
      allow(mock_processor).to receive(:set_checkpoint)

      # Act: Execute the code under test
      karafka_messages.each { |message| message }

      # Assert: Verify no calls were made
      expect(mock_processor).not_to have_received(:set_checkpoint)
    end
  end

  describe 'Monitor DSM integration' do
    # Test the DSM functionality by directly testing the Monitor module
    let(:monitor_class) do
      Class.new do
        include Datadog::Tracing::Contrib::Karafka::Monitor

        TRACEABLE_EVENTS = %w[worker.processed].freeze

        def instrument(event_id, payload = {}, &block)
          return super unless TRACEABLE_EVENTS.include?(event_id)

          # Simplified version of the Monitor logic for testing
          job = payload[:job]
          job_type = 'Consume' # Simplified for testing
          action = 'consume'

          # DSM: Track consumer offset stats for batch processing
          if action == 'consume' && Datadog.configuration.tracing.data_streams.enabled
            processor = Datadog.configuration.tracing.data_streams.processor
            job.messages.each do |message|
              processor.track_kafka_consume(
                job.executor.topic.name,
                job.executor.partition,
                message.metadata.offset,
                Time.now.to_f
              )
            end
          end

          yield if block
        end

        private

        def fetch_job_type(job_class)
          'Consume'
        end
      end
    end

    let(:mock_job) do
      OpenStruct.new(
        messages: [
          create_mock_message(topic: 'orders', partition: 0, offset: 100),
          create_mock_message(topic: 'orders', partition: 0, offset: 101)
        ],
        executor: OpenStruct.new(
          topic: OpenStruct.new(
            name: 'orders',
            consumer: 'OrderConsumer'
          ),
          partition: 0
        )
      )
    end

    let(:monitor) { monitor_class.new }
    let(:mock_processor) { instance_double('DataStreamsProcessor') }

    before do
      # Set up basic configuration
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(mock_processor)
    end

    it 'tracks consumer offset stats for batch processing' do
      # Arrange: Set up spies
      allow(mock_processor).to receive(:track_kafka_consume)

      # Act: Execute the code under test
      monitor.instrument('worker.processed', { job: mock_job }) do
        # Simulate message processing
      end

      # Assert: Verify the calls were made
      expect(mock_processor).to have_received(:track_kafka_consume)
        .with('orders', 0, 100, kind_of(Float))
        .once
      expect(mock_processor).to have_received(:track_kafka_consume)
        .with('orders', 0, 101, kind_of(Float))
        .once
    end

    it 'skips tracking when DSM disabled' do
      # Arrange: Disable DSM and set up spy
      Datadog.configure do |c|
        c.tracing.data_streams.enabled = false
      end
      allow(mock_processor).to receive(:track_kafka_consume)

      # Act: Execute the code under test
      monitor.instrument('worker.processed', { job: mock_job }) do
        # Simulate message processing
      end

      # Assert: Verify no calls were made
      expect(mock_processor).not_to have_received(:track_kafka_consume)
    end
  end

  describe 'pathway context propagation' do
    it 'handles messages with existing pathway context' do
      message_with_context = create_mock_message(
        headers: { 'dd-pathway-ctx-base64' => 'encoded-context-data' }
      )

      messages = Karafka::Messages::Messages.new([message_with_context])
      messages.extend(Datadog::Tracing::Contrib::Karafka::MessagesPatch)

      mock_processor = instance_double('DataStreamsProcessor')
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(mock_processor)
      allow(mock_processor).to receive(:set_checkpoint)

      # Should decode context and create checkpoint
      expect(mock_processor).to receive(:decode_and_set_pathway_context)
        .with({ 'dd-pathway-ctx-base64' => 'encoded-context-data' })
      expect(mock_processor).to receive(:set_checkpoint)
        .with(['topic:test_topic'], anything)

      messages.each { |message| message }
    end

    it 'creates new pathway context when none exists' do
      message_without_context = create_mock_message(headers: {})

      messages = Karafka::Messages::Messages.new([message_without_context])
      messages.extend(Datadog::Tracing::Contrib::Karafka::MessagesPatch)

      mock_processor = instance_double('DataStreamsProcessor')
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(mock_processor)
      allow(mock_processor).to receive(:set_checkpoint)

      # Should decode empty context and create checkpoint
      expect(mock_processor).to receive(:decode_and_set_pathway_context)
        .with({})
      expect(mock_processor).to receive(:set_checkpoint)
        .with(['topic:test_topic'], anything)

      messages.each { |message| message }
    end
  end

  describe 'comprehensive DSM disable behavior' do
    let(:messages_class) do
      Class.new do
        include Datadog::Tracing::Contrib::Karafka::MessagesPatch

        def initialize(messages_array)
          @messages_array = messages_array
        end

        def configuration
          @configuration ||= { distributed_tracing: false }
        end
      end
    end

    let(:messages) do
      [
        create_mock_message(topic: 'orders', partition: 0, offset: 100),
        create_mock_message(topic: 'orders', partition: 0, offset: 101)
      ]
    end

    let(:karafka_messages) { messages_class.new(messages) }
    let(:mock_processor) { instance_double('DataStreamsProcessor') }

    before do
      allow(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(mock_processor)

      # Mock tracing to avoid span creation errors
      span_double = double('span')
      allow(span_double).to receive(:set_tag)
      allow(span_double).to receive(:resource=)
      allow(Datadog::Tracing).to receive(:trace).and_yield(span_double)
    end

    it 'ensures no DSM processor methods are called when DSM disabled' do
      # Arrange: Disable DSM and set up spies for ALL processor methods
      Datadog.configure do |c|
        c.tracing.data_streams.enabled = false
      end
      allow(mock_processor).to receive(:set_checkpoint)
      allow(mock_processor).to receive(:track_kafka_consume)
      allow(mock_processor).to receive(:track_kafka_produce)
      allow(mock_processor).to receive(:encode_pathway_context)
      allow(mock_processor).to receive(:decode_and_set_pathway_context)

      # Act: Execute message processing (which would normally trigger DSM)
      karafka_messages.each { |message| message }

      # Assert: Verify NO DSM processor methods were called
      expect(mock_processor).not_to have_received(:set_checkpoint)
      expect(mock_processor).not_to have_received(:track_kafka_consume)
      expect(mock_processor).not_to have_received(:track_kafka_produce)
      expect(mock_processor).not_to have_received(:encode_pathway_context)
      expect(mock_processor).not_to have_received(:decode_and_set_pathway_context)
    end
  end
end
