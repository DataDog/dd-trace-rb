# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/core'
require 'datadog/core/ddsketch'
require 'datadog/data_streams/spec_helper'
require 'karafka'
require 'ostruct'

RSpec.describe 'Karafka Data Streams Integration' do
  # Helper to create Karafka Messages using the real API
  def build_karafka_messages(messages_data, topic_name = 'test_topic', partition = 0)
    # Mock the topic with required methods (API changed between Karafka versions)
    deserializer_mock = double('deserializer')
    allow(deserializer_mock).to receive(:payload).and_return(double(call: nil))
    allow(deserializer_mock).to receive(:key).and_return(double(call: nil))
    allow(deserializer_mock).to receive(:headers).and_return(double(call: nil))

    topic = double('Karafka::Routing::Topic',
      name: topic_name,
      deserializer: deserializer_mock,   # Karafka 2.3.0 (singular)
      deserializers: deserializer_mock,  # Karafka 2.5+ (plural)
      consumer_group: double(id: 'test_group'))

    raw_messages = messages_data.map do |data|
      # Create metadata double
      metadata = double('metadata')
      allow(metadata).to receive(:partition).and_return(data[:partition] || partition)
      allow(metadata).to receive(:offset).and_return(data[:offset] || 100)
      allow(metadata).to receive(:headers).and_return(data[:headers] || {})
      allow(metadata).to receive(:raw_headers).and_return(data[:headers] || {})
      allow(metadata).to receive(:respond_to?).with(:raw_headers).and_return(true)

      # Create message double
      msg = double('Karafka::Messages::Message')
      allow(msg).to receive(:topic).and_return(data[:topic] || topic_name)
      allow(msg).to receive(:partition).and_return(data[:partition] || partition)
      allow(msg).to receive(:offset).and_return(data[:offset] || 100)
      allow(msg).to receive(:headers).and_return(data[:headers] || {})
      allow(msg).to receive(:key).and_return(nil)
      allow(msg).to receive(:payload).and_return(nil)
      allow(msg).to receive(:timestamp).and_return(Time.now)
      allow(msg).to receive(:metadata).and_return(metadata)
      msg
    end

    ::Karafka::Messages::Builders::Messages.call(raw_messages, topic, partition, Time.now)
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :karafka
      c.data_streams.enabled = true
    end
  end

  after do
    Datadog::DataStreams.send(:processor)&.stop(true)
  end

  describe 'auto-instrumentation' do
    before do
      skip_if_data_streams_not_supported(self)
    end

    it 'automatically extracts and processes pathway context when consuming messages' do
      processor = Datadog::DataStreams.send(:processor)

      # Producer creates pathway context (simulating message from another service)
      producer_ctx_b64 = processor.set_produce_checkpoint(type: 'kafka', destination: 'orders')
      producer_ctx = Datadog::DataStreams::PathwayContext.decode_b64(producer_ctx_b64)

      # Create Karafka message with the pathway context in headers
      messages = build_karafka_messages([
        {topic: 'orders', partition: 0, offset: 100, headers: {'dd-pathway-ctx-base64' => producer_ctx_b64}}
      ], 'orders')

      # When we call .each, auto-instrumentation automatically:
      # 1. Extracts pathway context from headers
      # 2. Calls set_consume_checkpoint
      # 3. Updates the processor's pathway context
      messages.each do |message|
        # Verify message has the pathway context
        expect(message.headers['dd-pathway-ctx-base64']).to eq(producer_ctx_b64)

        # Verify auto-instrumentation has processed it
        current_ctx = processor.instance_variable_get(:@pathway_context)
        expect(current_ctx).to be_a(Datadog::DataStreams::PathwayContext)
        expect(current_ctx.hash).not_to eq(producer_ctx.hash) # Consume checkpoint has different hash
        expect(current_ctx.pathway_start).to be_within(0.001).of(producer_ctx.pathway_start) # Same pathway (within 1ms due to serialization precision loss)
      end
    end

    it 'creates new pathway context when headers are missing' do
      processor = Datadog::DataStreams.send(:processor)

      messages = build_karafka_messages([
        {topic: 'orders', partition: 0, offset: 100, headers: {}}
      ], 'orders')

      # Auto-instrumentation should still create a consume checkpoint even without headers
      messages.each { |_message| }

      new_ctx = processor.instance_variable_get(:@pathway_context)
      expect(new_ctx).to be_a(Datadog::DataStreams::PathwayContext)
      expect(new_ctx.hash).to be > 0
    end

    it 'processes multiple messages in a batch' do
      processor = Datadog::DataStreams.send(:processor)

      messages = build_karafka_messages([
        {topic: 'orders', partition: 0, offset: 100},
        {topic: 'orders', partition: 0, offset: 101},
        {topic: 'orders', partition: 0, offset: 102}
      ], 'orders')

      message_count = 0
      expect {
        messages.each do |_message|
          message_count += 1
          # Each message gets auto-instrumentation
        end
      }.not_to raise_error

      expect(message_count).to eq(3)
      expect(processor.pathway_context.hash).to be > 0
    end
  end

  describe 'pathway propagation across services' do
    before do
      skip_if_data_streams_not_supported(self)
    end

    it 'maintains pathway continuity through produce → consume → produce chain' do
      processor = Datadog::DataStreams.send(:processor)

      # Service A: Producer creates initial pathway
      ctx_a_b64 = processor.set_produce_checkpoint(type: 'kafka', destination: 'orders-topic')
      ctx_a = Datadog::DataStreams::PathwayContext.decode_b64(ctx_a_b64)

      # Service B: Consumes from Service A (auto-instrumentation processes it)
      messages_from_a = build_karafka_messages([
        {topic: 'orders-topic', partition: 0, offset: 100, headers: {'dd-pathway-ctx-base64' => ctx_a_b64}}
      ], 'orders-topic')

      messages_from_a.each { |_msg| } # Auto-instrumentation runs here

      ctx_b_consume = processor.instance_variable_get(:@pathway_context)
      expect(ctx_b_consume.hash).not_to eq(ctx_a.hash) # Consume creates new checkpoint
      expect(ctx_b_consume.pathway_start).to be_within(0.001).of(ctx_a.pathway_start) # Same pathway (within 1ms due to serialization precision loss)

      # Service B: Produces to next topic
      ctx_b_produce_b64 = processor.set_produce_checkpoint(type: 'kafka', destination: 'processed-orders')
      ctx_b_produce = Datadog::DataStreams::PathwayContext.decode_b64(ctx_b_produce_b64)

      # Verify it's still the same pathway (within 1ms due to serialization precision loss)
      expect(ctx_b_produce.pathway_start).to be_within(0.001).of(ctx_a.pathway_start)

      # Service C: Consumes from Service B (auto-instrumentation processes it)
      messages_from_b = build_karafka_messages([
        {topic: 'processed-orders', partition: 0, offset: 200, headers: {'dd-pathway-ctx-base64' => ctx_b_produce_b64}}
      ], 'processed-orders')

      messages_from_b.each { |_msg| } # Auto-instrumentation runs here

      ctx_c = processor.instance_variable_get(:@pathway_context)
      expect(ctx_c).to be_a(Datadog::DataStreams::PathwayContext)
      expect(ctx_c.hash).to be > 0
      expect(ctx_c.pathway_start).to be_within(0.001).of(ctx_a.pathway_start) # Still same original pathway (within 1ms due to serialization precision loss)

      # Verify pathway progressed through all services
      # At minimum, consume from A should create different hash than initial produce
      expect(ctx_b_consume.hash).not_to eq(ctx_a.hash)
    end
  end

  describe 'when DSM is disabled' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :karafka
        c.data_streams.enabled = false
      end
    end

    it 'skips DSM processing' do
      messages = build_karafka_messages([
        {topic: 'orders', partition: 0, offset: 100, headers: {'dd-pathway-ctx-base64' => 'some-context'}}
      ], 'orders')

      # Should not raise error even though DSM is disabled
      expect {
        messages.each { |_message| }
      }.not_to raise_error
    end
  end
end
