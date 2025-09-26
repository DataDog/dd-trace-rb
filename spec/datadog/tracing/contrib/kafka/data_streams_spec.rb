# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'ostruct'
require 'datadog/tracing/contrib/kafka/integration'
require 'datadog/tracing/contrib/kafka/instrumentation/producer'
require 'datadog/tracing/contrib/kafka/instrumentation/consumer'
# Mock required classes
module Gem
  def self.loaded_specs
    { 'ruby-kafka' => OpenStruct.new(version: Gem::Version.new('1.5.0')) }
  end
end

module ActiveSupport
  module Notifications
    def self.subscribe(*_args); end
  end
end

# Mock Kafka classes that we need
module Kafka
  class Producer
    def deliver_messages(messages = [], **kwargs)
      { delivered_count: messages.size }
    end

    def send_messages(messages, **kwargs)
      { sent_count: messages.size }
    end
  end

  class Consumer
    def each_message(**kwargs)
      if block_given?
        yield OpenStruct.new(
          topic: 'test_topic',
          partition: 0,
          offset: 100,
          headers: {}
        )
      end
    end

    def each_batch(**kwargs)
      if block_given?
        yield OpenStruct.new(
          topic: 'test_topic',
          partition: 0,
          messages: [
            OpenStruct.new(offset: 100, key: 'key1'),
            OpenStruct.new(offset: 101, key: 'key2')
          ]
        )
      end
    end
  end
end
require 'datadog'

RSpec.describe 'Kafka Data Streams instrumentation' do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :kafka, configuration_options
      c.tracing.data_streams.enabled = true
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:kafka].reset_configuration!
    example.run
    Datadog.registry[:kafka].reset_configuration!
  end

  describe 'pathway context' do
    let(:test_producer_class) do
      Class.new do
        def deliver_messages(messages = [], **kwargs)
          messages.each do |message|
            # We'll implement header injection here
            message[:headers] ||= {}
          end
          { delivered_count: messages.size }
        end

        include Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer
      end
    end

    let(:producer) { test_producer_class.new }
    let(:message) { { topic: 'test_topic', value: 'test_value' } }

    it 'injects pathway context into message headers' do
      producer.deliver_messages([message])

      # Initial test just verifies basic structure until we implement context
      expect(message[:headers]).to include('dd-pathway-ctx-base64')
      expect(message[:headers]['dd-pathway-ctx-base64']).to be_a(String)
    end

    it 'creates new pathway context for first message' do
      producer.deliver_messages([message])

      # We'll expand this once we implement context decoding
      encoded_ctx = message[:headers]['dd-pathway-ctx-base64']
      expect(encoded_ctx).not_to be_nil
    end
  end

  describe 'checkpointing' do
    let(:test_consumer_class) do
      Class.new do
        def each_message(**kwargs)
          message = OpenStruct.new(
            topic: 'test_topic',
            partition: 0,
            offset: 100,
            headers: {
              'dd-pathway-ctx-base64' => nil # We'll set this in tests
            }
          )
          yield(message) if block_given?
        end

        include Datadog::Tracing::Contrib::Kafka::Instrumentation::Consumer
      end
    end

    let(:consumer) { test_consumer_class.new }

    it 'creates checkpoint on message consume' do
      # This will fail until we implement checkpointing
      expect(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(instance_double('DataStreamsProcessor', set_checkpoint: true, encode_pathway_context: 'test-context'))

      consumer.each_message do |msg|
        # Message is processed
      end
    end
  end

  describe 'stats collection' do
    let(:test_producer_class) do
      Class.new do
        def deliver_messages(messages = [], **kwargs)
          messages.each do |message|
            # Track produce offset
            @last_offset = rand(1000)
          end
          { delivered_count: messages.size }
        end

        include Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer
      end
    end

    let(:producer) { test_producer_class.new }
    let(:message) { { topic: 'test_topic', value: 'test_value' } }

    it 'tracks produce offsets' do
      # This will fail until we implement offset tracking
      expect(Datadog.configuration.tracing.data_streams).to receive(:processor)
        .and_return(instance_double(
          'DataStreamsProcessor',
          track_kafka_produce: true,
          encode_pathway_context: 'test-context'
        ))

      producer.deliver_messages([message])
    end
  end
end
