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
require 'datadog/tracing/contrib/racecar/instrumentation/consumer'
require 'datadog/tracing/contrib/racecar/instrumentation/producer'

RSpec.describe 'Racecar Data Streams instrumentation' do
  let(:configuration_options) { {} }
  let(:propagation_key) { Datadog::DataStreams::Processor::PROPAGATION_KEY }

  # Stand-in for a single rdkafka message: only the attributes the
  # instrumentation reads.
  def build_message(topic: 'test_topic', partition: 0, offset: 100, headers: {})
    instance_double(
      Rdkafka::Consumer::Message,
      topic: topic,
      partition: partition,
      offset: offset,
      headers: headers,
    )
  end

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

  # Drives the prepended Racecar::Runner#process / #process_batch without a live
  # Kafka connection by stubbing the base methods the instrumentation calls super on.
  let(:runner_class) do
    Class.new do
      attr_reader :processed

      def initialize
        @processed = []
      end

      def process(message)
        @processed << message
      end

      def process_batch(messages)
        @processed.concat(messages)
      end

      prepend Datadog::Tracing::Contrib::Racecar::Instrumentation::Consumer
    end
  end

  let(:runner) { runner_class.new }

  describe 'consuming a single message' do
    before do
      skip_if_libdatadog_not_supported
    end

    subject(:consume) { runner.process(message) }

    context 'with a pathway context in the message headers' do
      let(:message) do
        build_message(headers: {propagation_key => 'upstream-context'})
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

      it 'still processes the message' do
        consume

        expect(runner.processed).to eq([message])
      end
    end

    context 'with symbol-keyed headers (rdkafka <= 0.12)' do
      let(:message) do
        build_message(headers: {propagation_key.to_sym => 'upstream-context'})
      end

      it 'extracts the upstream pathway context regardless of key type' do
        extracted = nil
        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint) do |**_kwargs, &block|
          extracted = block.call(propagation_key)
        end

        consume

        expect(extracted).to eq('upstream-context')
      end
    end

    context 'without a pathway context in the headers' do
      let(:message) { build_message(headers: {}) }

      it 'still sets a consume checkpoint without raising' do
        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
          .with(type: 'kafka', source: 'test_topic', auto_instrumentation: true)

        expect { consume }.not_to raise_error
      end
    end

    context 'with nil headers' do
      let(:message) { build_message(headers: nil) }

      it 'sets a consume checkpoint without raising' do
        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
          .with(type: 'kafka', source: 'test_topic', auto_instrumentation: true)

        expect { consume }.not_to raise_error
      end
    end

    context 'when setting the checkpoint raises' do
      let(:message) { build_message(headers: {propagation_key => 'upstream-context'}) }

      before do
        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint).and_raise('boom')
      end

      it 'does not disrupt message processing' do
        expect { consume }.not_to raise_error
        expect(runner.processed).to eq([message])
      end
    end
  end

  describe 'consuming a batch' do
    before do
      skip_if_libdatadog_not_supported
    end

    subject(:consume_batch) { runner.process_batch(messages) }

    # Two messages from different source topics merging into one step: each must
    # keep its own upstream context (N:1 fan-in).
    let(:messages) do
      [
        build_message(topic: 'source_a', partition: 0, offset: 100, headers: {propagation_key => 'ctx-a'}),
        build_message(topic: 'source_b', partition: 1, offset: 200, headers: {propagation_key => 'ctx-b'}),
      ]
    end

    it 'sets a consume checkpoint per message, preserving each source' do
      expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
        .with(type: 'kafka', source: 'source_a', auto_instrumentation: true).ordered
      expect(Datadog::DataStreams).to receive(:set_consume_checkpoint)
        .with(type: 'kafka', source: 'source_b', auto_instrumentation: true).ordered

      consume_batch
    end

    it 'extracts each message\'s own upstream pathway context' do
      extracted = []
      allow(Datadog::DataStreams).to receive(:set_consume_checkpoint) do |**_kwargs, &block|
        extracted << block.call(propagation_key)
      end

      consume_batch

      expect(extracted).to eq(['ctx-a', 'ctx-b'])
    end

    it 'tracks the consumed offset for every message' do
      expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('source_a', 0, 100)
      expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('source_b', 1, 200)

      consume_batch
    end

    it 'still processes the batch' do
      consume_batch

      expect(runner.processed).to eq(messages)
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

    it 'does not set a checkpoint when consuming a message with a pathway context' do
      expect(Datadog::DataStreams).not_to receive(:set_consume_checkpoint)

      message = build_message(headers: {propagation_key => 'some-context'})

      expect { runner.process(message) }.not_to raise_error
      expect(runner.processed).to eq([message])
    end
  end
end
