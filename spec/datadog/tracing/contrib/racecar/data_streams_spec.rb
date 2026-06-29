# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/core'
require 'datadog/core/ddsketch'

require 'spec/support/thread_helpers'

# FFI::Function background native thread
ThreadHelpers.with_leaky_thread_creation(:racecar) do
  require 'racecar'
end

require 'racecar/cli'
require 'active_support'
require 'datadog'
require 'datadog/tracing/contrib/racecar/instrumentation/producer'

RSpec.describe 'Racecar Data Streams instrumentation' do
  let(:configuration_options) { {} }
  let(:propagation_key) { Datadog::DataStreams::Processor::PROPAGATION_KEY }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :racecar, configuration_options
      c.data_streams.enabled = true
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:racecar].reset_configuration!
    example.run
    Datadog.registry[:racecar].reset_configuration!
  end

  describe 'consuming a single message' do
    before do
      skip_if_libdatadog_not_supported
    end

    subject(:consume) do
      ActiveSupport::Notifications.instrument('process_message.racecar', payload)
    end

    context 'with a pathway context in the message headers' do
      let(:payload) do
        {
          consumer_class: 'TestConsumer',
          topic: 'test_topic',
          partition: 0,
          offset: 100,
          headers: {propagation_key => 'upstream-context'},
        }
      end

      it 'sets a consume checkpoint for the topic' do
        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
          .with(type: 'kafka', source: 'test_topic', auto_instrumentation: true)

        consume
      end

      it 'extracts the upstream pathway context from the message headers' do
        extracted = nil
        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint) do |**_kwargs, &block|
          extracted = block.call(propagation_key)
        end

        consume

        expect(extracted).to eq('upstream-context')
      end

      it 'tracks the consumed offset for consumer lag' do
        expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('test_topic', 0, 100)

        consume
      end
    end

    context 'without headers in the payload' do
      let(:payload) do
        {
          consumer_class: 'TestConsumer',
          topic: 'test_topic',
          partition: 0,
          offset: 100,
        }
      end

      it 'still sets a consume checkpoint without raising' do
        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
          .with(type: 'kafka', source: 'test_topic', auto_instrumentation: true)

        expect { consume }.not_to raise_error
      end
    end
  end

  describe 'consuming a batch' do
    before do
      skip_if_libdatadog_not_supported
    end

    subject(:consume_batch) do
      ActiveSupport::Notifications.instrument('process_batch.racecar', payload)
    end

    let(:payload) do
      {
        consumer_class: 'TestConsumer',
        topic: 'test_topic',
        partition: 0,
        first_offset: 100,
        last_offset: 110,
        message_count: 11,
      }
    end

    it 'sets a topic-level consume checkpoint' do
      expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
        .with(type: 'kafka', source: 'test_topic', auto_instrumentation: true)

      consume_batch
    end

    it 'tracks the last consumed offset for consumer lag' do
      expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('test_topic', 0, 110)

      consume_batch
    end
  end

  describe 'producing a message from a consumer' do
    before do
      skip_if_libdatadog_not_supported
    end

    let(:consumer_class) do
      Class.new(::Racecar::Consumer) do
        def produce_test(headers: nil)
          captured = nil
          # Stub the internal producer so we capture what would be sent.
          producer = Object.new
          producer.define_singleton_method(:produce) do |**kwargs|
            captured = kwargs
            :handle
          end
          define_singleton_method(:captured) { captured }
          @producer = producer
          @delivery_handles = []
          @instrumenter = ::Racecar::NullInstrumenter

          send(:produce, 'payload', topic: 'out_topic', headers: headers)
        end
      end
    end

    it 'injects pathway context into the message headers' do
      consumer = consumer_class.new
      consumer.produce_test

      headers = consumer.captured[:headers]
      expect(headers).to be_a(Hash)

      encoded_ctx = headers[propagation_key]
      expect(encoded_ctx).to be_a(String)
      expect(encoded_ctx).not_to be_empty

      decoded_ctx = Datadog::DataStreams::PathwayContext.decode_b64(encoded_ctx)
      expect(decoded_ctx).to be_a(Datadog::DataStreams::PathwayContext)
      expect(decoded_ctx.hash).to be > 0
    end

    it 'preserves caller-provided headers' do
      consumer = consumer_class.new
      consumer.produce_test(headers: {'custom' => 'value'})

      headers = consumer.captured[:headers]
      expect(headers['custom']).to eq('value')
      expect(headers[propagation_key]).to be_a(String)
    end
  end

  describe 'producing a message from the standalone producer' do
    before do
      skip_if_libdatadog_not_supported
      # The standalone Racecar::Producer was introduced after the minimum
      # supported version, so it is not present in every tested version.
      skip('Racecar::Producer is not available in this version') unless defined?(::Racecar::Producer)
    end

    let(:producer_class) do
      Class.new(::Racecar::Producer) do
        def initialize
          @internal_producer = Object.new
          @delivery_handles = []
          @batching = false
          @instrumenter = ::Racecar::NullInstrumenter
          define_captured
        end

        def define_captured
          captured = nil
          @internal_producer.define_singleton_method(:produce) do |**kwargs|
            captured = kwargs
            :handle
          end
          define_singleton_method(:captured) { captured }
        end
      end
    end

    it 'injects pathway context when producing asynchronously' do
      producer = producer_class.new
      producer.produce_async(value: 'payload', topic: 'out_topic')

      headers = producer.captured[:headers]
      expect(headers).to be_a(Hash)
      expect(headers[propagation_key]).to be_a(String)
    end
  end

  describe 'when DSM is disabled' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :racecar
        c.data_streams.enabled = false
      end
    end

    let(:consumer_class) do
      Class.new(::Racecar::Consumer) do
        def produce_test
          captured = nil
          producer = Object.new
          producer.define_singleton_method(:produce) do |**kwargs|
            captured = kwargs
            :handle
          end
          define_singleton_method(:captured) { captured }
          @producer = producer
          @delivery_handles = []
          @instrumenter = ::Racecar::NullInstrumenter

          send(:produce, 'payload', topic: 'out_topic', headers: nil)
        end
      end
    end

    it 'does not inject DSM headers when producing' do
      consumer = consumer_class.new
      consumer.produce_test

      headers = consumer.captured[:headers]
      expect(headers).to be_nil.or(satisfy { |h| !h.key?(Datadog::DataStreams::Processor::PROPAGATION_KEY) })
    end

    it 'does not raise when consuming a message with a pathway context' do
      payload = {
        consumer_class: 'TestConsumer',
        topic: 'test_topic',
        partition: 0,
        offset: 100,
        headers: {Datadog::DataStreams::Processor::PROPAGATION_KEY => 'some-context'},
      }

      expect {
        ActiveSupport::Notifications.instrument('process_message.racecar', payload)
      }.not_to raise_error
    end
  end
end
