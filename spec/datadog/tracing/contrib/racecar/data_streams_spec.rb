# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/racecar/event'
require 'datadog/tracing/contrib/racecar/ext'

RSpec.describe 'Racecar Data Streams Integration' do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :racecar
      c.data_streams.enabled = true
    end
  end

  after do
    Datadog.configuration.reset!
  end

  # Helper to simulate ActiveSupport::Notifications payload for process_message
  def message_payload(topic:, partition:, offset:, headers: {}, consumer_class: 'TestConsumer')
    {
      consumer_class: consumer_class,
      topic: topic,
      partition: partition,
      offset: offset,
      create_time: Time.now,
      key: nil,
      value: 'test message',
      headers: headers
    }
  end

  # Helper to simulate ActiveSupport::Notifications payload for process_batch
  def batch_payload(topic:, partition:, first_offset:, last_offset:, message_count:, consumer_class: 'TestConsumer')
    {
      consumer_class: consumer_class,
      topic: topic,
      partition: partition,
      first_offset: first_offset,
      last_offset: last_offset,
      last_create_time: Time.now,
      message_count: message_count
    }
  end

  # Create a test class that includes the Event module to access ClassMethods
  let(:event_class) do
    Class.new do
      extend Datadog::Tracing::Contrib::Racecar::Event::ClassMethods
    end
  end

  describe 'single message processing (process_message event)' do
    context 'when DSM is enabled and supported' do
      before do
        skip 'DSM not supported' unless defined?(Datadog::DataStreams) && Datadog::DataStreams.respond_to?(:enabled?)
        allow(Datadog::DataStreams).to receive(:enabled?).and_return(true)
      end

      it 'extracts pathway context from message headers and sets consume checkpoint' do
        payload = message_payload(
          topic: 'orders',
          partition: 0,
          offset: 100,
          headers: {'dd-pathway-ctx-base64' => 'some-encoded-context'}
        )

        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint).with(
          type: 'kafka',
          source: 'orders',
          auto_instrumentation: true
        ).and_yield('dd-pathway-ctx-base64')

        expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('orders', 0, 100)

        event_class.send(:set_dsm_checkpoint, payload)
      end

      it 'handles missing headers gracefully' do
        payload = message_payload(
          topic: 'orders',
          partition: 0,
          offset: 100,
          headers: {}
        )

        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint).with(
          type: 'kafka',
          source: 'orders',
          auto_instrumentation: true
        )

        expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('orders', 0, 100)

        event_class.send(:set_dsm_checkpoint, payload)
      end

      it 'tracks kafka consume offset for lag monitoring' do
        payload = message_payload(
          topic: 'test-topic',
          partition: 2,
          offset: 42,
          headers: {}
        )

        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint)
        expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('test-topic', 2, 42)

        event_class.send(:set_dsm_checkpoint, payload)
      end
    end
  end

  describe 'batch processing (process_batch event)' do
    context 'when DSM is enabled and supported' do
      before do
        skip 'DSM not supported' unless defined?(Datadog::DataStreams) && Datadog::DataStreams.respond_to?(:enabled?)
        allow(Datadog::DataStreams).to receive(:enabled?).and_return(true)
      end

      it 'sets consume checkpoint for batch' do
        payload = batch_payload(
          topic: 'orders',
          partition: 0,
          first_offset: 100,
          last_offset: 109,
          message_count: 10
        )

        expect(Datadog::DataStreams).to receive(:set_consume_checkpoint).with(
          type: 'kafka',
          source: 'orders',
          auto_instrumentation: true
        )

        expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('orders', 0, 109)

        event_class.send(:set_dsm_checkpoint, payload)
      end

      it 'tracks the last offset in batch for lag monitoring' do
        payload = batch_payload(
          topic: 'batch-topic',
          partition: 1,
          first_offset: 100,
          last_offset: 199,
          message_count: 100
        )

        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint)
        expect(Datadog::DataStreams).to receive(:track_kafka_consume).with('batch-topic', 1, 199)

        event_class.send(:set_dsm_checkpoint, payload)
      end
    end
  end

  describe 'when DSM is disabled' do
    before do
      Datadog.configure do |c|
        c.data_streams.enabled = false
      end
    end

    it 'skips DSM processing for single messages' do
      payload = message_payload(
        topic: 'orders',
        partition: 0,
        offset: 100,
        headers: {'dd-pathway-ctx-base64' => 'some-context'}
      )

      expect(Datadog::DataStreams).not_to receive(:set_consume_checkpoint)
      expect(Datadog::DataStreams).not_to receive(:track_kafka_consume)

      # Should not raise error
      expect { event_class.send(:set_dsm_checkpoint, payload) }.not_to raise_error
    end

    it 'skips DSM processing for batches' do
      payload = batch_payload(
        topic: 'orders',
        partition: 0,
        first_offset: 100,
        last_offset: 109,
        message_count: 10
      )

      expect(Datadog::DataStreams).not_to receive(:set_consume_checkpoint)
      expect(Datadog::DataStreams).not_to receive(:track_kafka_consume)

      expect { event_class.send(:set_dsm_checkpoint, payload) }.not_to raise_error
    end
  end

  describe 'error handling' do
    context 'when DSM is enabled' do
      before do
        skip 'DSM not supported' unless defined?(Datadog::DataStreams) && Datadog::DataStreams.respond_to?(:enabled?)
        allow(Datadog::DataStreams).to receive(:enabled?).and_return(true)
      end

      it 'logs and continues on DSM errors' do
        payload = message_payload(
          topic: 'orders',
          partition: 0,
          offset: 100,
          headers: {}
        )

        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint).and_raise(StandardError.new('DSM error'))
        expect(Datadog.logger).to receive(:debug).with(/Error setting Racecar DSM checkpoint/)

        # Should not raise, just log
        expect { event_class.send(:set_dsm_checkpoint, payload) }.not_to raise_error
      end
    end
  end
end
