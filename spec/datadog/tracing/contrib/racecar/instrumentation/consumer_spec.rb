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

RSpec.describe Datadog::Tracing::Contrib::Racecar::Instrumentation::Consumer do
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
      c.tracing.instrument :racecar
      c.data_streams.enabled = data_streams_enabled
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:racecar].reset_configuration!
    example.run
    Datadog.registry[:racecar].reset_configuration!
  end

  let(:data_streams_enabled) { true }

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

    context 'when Data Streams Monitoring is disabled' do
      let(:data_streams_enabled) { false }
      let(:message) { build_message(headers: {propagation_key => 'upstream-context'}) }

      it 'does not set a checkpoint but still processes the message' do
        expect(Datadog::DataStreams).not_to receive(:set_consume_checkpoint)

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
end
