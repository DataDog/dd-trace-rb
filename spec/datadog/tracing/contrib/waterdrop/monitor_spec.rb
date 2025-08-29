# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

# FFI::Function background native thread
ThreadHelpers.with_leaky_thread_creation(:rdkafka) do
  require 'waterdrop'
end
require 'datadog'

puts "waterdrop version: #{WaterDrop::VERSION}"

RSpec.describe 'Waterdrop monitor' do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :waterdrop, tracing_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:waterdrop].reset_configuration!
    example.run
    Datadog.registry[:waterdrop].reset_configuration!
  end

  let(:producer) do
    WaterDrop::Producer.new do |config|
      # Dummy - doesn't try to connect to Kafka
      config.client_class = WaterDrop::Clients::Buffered
    end
  end

  let(:tracing_options) { { distributed_tracing: false } }

  describe '.instrument' do
    context 'when the event is not traceable' do
      it 'does not create a trace' do
        producer.monitor.instrument('transaction.started')

        # NOTE: This helper doesn't workt with `change` matcher well.
        expect(traces).to have(0).items
        expect(spans).to have(0).items
      end
    end

    context 'when the event is message.produced_async' do
      it 'traces a producer job' do
        producer.monitor.instrument(
          'message.produced_async',
          { producer_id: 'producer1', message: { topic: 'topic_name' } }
        )

        expect(traces).to have(1).item
        expect(spans).to have(1).item

        expect(spans[0].resource).to eq('waterdrop.produce_async')
        expect(spans[0].tags).to include(
          Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => 'producer1',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => 'topic_name',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 1
        )
      end
    end

    context 'when the event is message.produced_sync' do
      it 'traces a producer job' do
        producer.monitor.instrument(
          'message.produced_sync',
          { producer_id: 'producer1', message: { topic: 'topic_name', partition: 1 } }
        )

        expect(traces).to have(1).item
        expect(spans).to have(1).item

        expect(spans[0].resource).to eq('waterdrop.produce_sync')
        expect(spans[0].tags).to include(
          Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => 'producer1',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => 'topic_name',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => 1,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 1
        )
      end
    end

    context 'when the event is messages.produced_async' do
      it 'traces a producer job' do
        producer.monitor.instrument(
          'messages.produced_async',
          {
            producer_id: 'producer1',
            messages: [
              { topic: 'topic_name', payload: 'foo', partition: 1 },
              { topic: 'topic_name', payload: 'bar' },
              { topic: 'other_topic', payload: 'baz', partition: 0 },
            ],
          }
        )

        expect(traces).to have(1).item
        expect(spans).to have(1).item

        expect(spans[0].resource).to eq('waterdrop.produce_many_async')
        expect(spans[0].tags).to include(
          Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => 'producer1',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => '["topic_name", "other_topic"]',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => '[1, 0]',
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 3
        )
      end
    end

    context 'when the event is messages.produced_sync' do
      it 'traces a producer job' do
        producer.monitor.instrument(
          'messages.produced_sync',
          {
            producer_id: 'producer1',
            messages: [
              { topic: 'topic_name', payload: 'foo', partition: 1 },
              { topic: 'topic_name', payload: 'bar' },
              { topic: 'other_topic', payload: 'baz', partition: 0 },
            ],
          }
        )

        expect(traces).to have(1).item
        expect(spans).to have(1).item

        expect(spans[0].resource).to eq('waterdrop.produce_many_sync')
        expect(spans[0].tags).to include(
          Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => 'producer1',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => '["topic_name", "other_topic"]',
          Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => '[1, 0]',
          Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 3
        )
      end
    end

    context 'when distributed tracing is enabled and the event payload contains only one message' do
      let(:tracing_options) { { distributed_tracing: true } }

      it 'injects trace context into message headers' do
        message = { topic: 'topic_name', payload: 'foo', partition: 1 }

        producer.monitor.instrument('message.produced_async', message: message)

        # Check that the trace context was injected into the message headers
        expect(message[:headers]['x-datadog-trace-id']).to eq(low_order_trace_id(span.trace_id).to_s)
        expect(message[:headers]['x-datadog-parent-id']).to eq(span.id.to_s)
        expect(message[:headers]['x-datadog-sampling-priority']).to eq('1')
        expect(message[:headers]['x-datadog-tags'])
          .to eq("_dd.p.dm=-0,_dd.p.tid=#{high_order_hex_trace_id(span.trace_id)}")
      end
    end

    context 'when distributed tracing is enabled and the event payload contains many messages' do
      let(:tracing_options) { { distributed_tracing: true } }

      it "injects trace context into all of the messages' headers" do
        messages = [
          { topic: 'topic_name', payload: 'foo', partition: 1 },
          { topic: 'topic_name', payload: 'bar' },
          { topic: 'other_topic', payload: 'baz', partition: 0 },
        ]

        producer.monitor.instrument('messages.produced_async', messages: messages)

        # Check that the trace context was injected into the message headers
        messages.each do |message|
          expect(message[:headers]['x-datadog-trace-id']).to eq(low_order_trace_id(span.trace_id).to_s)
          expect(message[:headers]['x-datadog-parent-id']).to eq(span.id.to_s)
          expect(message[:headers]['x-datadog-sampling-priority']).to eq('1')
          expect(message[:headers]['x-datadog-tags'])
            .to eq("_dd.p.dm=-0,_dd.p.tid=#{high_order_hex_trace_id(span.trace_id)}")
        end
      end
    end
  end
end
