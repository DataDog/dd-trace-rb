# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

require 'ruby-kafka'
require 'active_support'
require 'datadog'
require 'ostruct'

RSpec.describe 'Kafka instrumentation via monkey patching' do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :kafka, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:kafka].reset_configuration!
    example.run
    Datadog.registry[:kafka].reset_configuration!
  end

  describe 'producer instrumentation' do
    # Create a minimal producer class for testing
    let(:test_producer_class) do
      Class.new do
        def deliver_messages(messages = [], **kwargs)
          # Simulate original behavior - normally would actually deliver messages
          { delivered_count: messages.size }
        end

        def send_messages(messages, **kwargs)
          # Simulate original async behavior
          { sent_count: messages.size }
        end

        # Include the instrumentation
        include Datadog::Tracing::Contrib::Kafka::Instrumentation::Producer
      end
    end

    let(:producer) { test_producer_class.new }
    let(:messages) do
      [
        { topic: 'test_topic_1', value: 'test_value_1' },
        { topic: 'test_topic_2', value: 'test_value_2' }
      ]
    end

        context 'when DSM is disabled (default)' do
      it 'calls deliver_messages and prints DSM disabled' do
        expect { producer.deliver_messages(messages) }.to output("deliver_messages (DSM disabled)\n").to_stdout
      end

      it 'calls send_messages and prints DSM disabled' do
        expect { producer.send_messages(messages) }.to output("send_messages (DSM disabled)\n").to_stdout
      end

      it 'preserves the original return value for deliver_messages' do
        expect {
          result = producer.deliver_messages(messages)
          expect(result).to eq({ delivered_count: 2 })
        }.to output("deliver_messages (DSM disabled)\n").to_stdout
      end
    end

    context 'when DSM is enabled' do
      before do
        Datadog.configure do |c|
          c.tracing.data_streams.enabled = true
        end
      end

      it 'calls deliver_messages and prints DSM enabled' do
        expect { producer.deliver_messages(messages) }.to output("deliver_messages (DSM enabled)\n").to_stdout
      end

      it 'calls send_messages and prints DSM enabled' do
        expect { producer.send_messages(messages) }.to output("send_messages (DSM enabled)\n").to_stdout
      end
    end
  end

  describe 'consumer instrumentation' do
    # Create a minimal consumer class for testing
    let(:test_consumer_class) do
      Class.new do
        def each_message(**kwargs)
          # Simulate consuming messages
          3.times do |i|
            message = OpenStruct.new(
              topic: 'test_topic',
              partition: 0,
              offset: 100 + i,
              key: "key_#{i}",
              value: "value_#{i}"
            )
            yield(message) if block_given?
          end
        end

        def each_batch(**kwargs)
          # Simulate batch processing
          batch = OpenStruct.new(
            topic: 'test_topic',
            partition: 0,
            messages: [
              OpenStruct.new(offset: 100, key: 'key1'),
              OpenStruct.new(offset: 101, key: 'key2')
            ]
          )
          yield(batch) if block_given?
        end

        # Include the instrumentation
        include Datadog::Tracing::Contrib::Kafka::Instrumentation::Consumer
      end
    end

    let(:consumer) { test_consumer_class.new }
    let(:consumed_messages) { [] }
    let(:consumed_batches) { [] }

        context 'when DSM is disabled (default)' do
      it 'calls each_message and prints DSM disabled' do
        expect do
          consumer.each_message do |msg|
            consumed_messages << msg
          end
        end.to output("each_message (DSM disabled)\n").to_stdout
      end

      it 'calls each_batch and prints DSM disabled' do
        expect do
          consumer.each_batch do |batch|
            consumed_batches << batch
          end
        end.to output("each_batch (DSM disabled)\n").to_stdout
      end

      it 'preserves message processing behavior' do
        expect do
          consumer.each_message do |msg|
            consumed_messages << msg
          end
        end.to output("each_message (DSM disabled)\n").to_stdout

        expect(consumed_messages).to have(3).items
        expect(consumed_messages.first.topic).to eq('test_topic')
        expect(consumed_messages.first.offset).to eq(100)
      end
    end

    context 'when DSM is enabled' do
      before do
        Datadog.configure do |c|
          c.tracing.data_streams.enabled = true
        end
      end

      it 'calls each_message and prints DSM enabled' do
        expect do
          consumer.each_message do |msg|
            consumed_messages << msg
          end
        end.to output("each_message (DSM enabled)\n").to_stdout
      end

      it 'calls each_batch and prints DSM enabled' do
        expect do
          consumer.each_batch do |batch|
            consumed_batches << batch
          end
        end.to output("each_batch (DSM enabled)\n").to_stdout
      end

      it 'preserves batch processing behavior' do
        expect do
          consumer.each_batch do |batch|
            consumed_batches << batch
          end
        end.to output("each_batch (DSM enabled)\n").to_stdout

        expect(consumed_batches).to have(1).item
        expect(consumed_batches.first.topic).to eq('test_topic')
        expect(consumed_batches.first.messages).to have(2).items
      end
    end
  end
end
