# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'
require 'waterdrop'
require 'datadog'

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

  let(:tracing_options) { {distributed_tracing: false} }

  describe '#produce_sync' do
    it 'traces a producer job' do
      producer.produce_sync(topic: 'some_topic', payload: 'hello', partition: 1)

      expect(span.name).to eq('karafka.produce')
      expect(span.resource).to eq('waterdrop.produce_sync')
      expect(span.tags).to include(
        Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => producer.id,
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 1,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => 'some_topic',
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => '1'
      )
    end
  end

  describe '#produce_async' do
    it 'traces a producer job' do
      producer.produce_async(topic: 'some_topic', payload: 'hello', partition: 1)

      expect(span.name).to eq('karafka.produce')
      expect(span.resource).to eq('waterdrop.produce_async')
      expect(span.tags).to include(
        Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => producer.id,
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 1,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => 'some_topic',
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => '1'
      )
    end
  end

  describe '#produce_many_sync' do
    it 'traces a producer job' do
      messages = [
        {topic: 'topic_name', payload: 'foo', partition: 1},
        {topic: 'topic_name', payload: 'bar'},
        {topic: 'other_topic', payload: 'baz', partition: 0},
      ].shuffle
      producer.produce_many_sync(messages)

      expect(span.name).to eq('karafka.produce')
      expect(span.resource).to eq('waterdrop.produce_many_sync')
      expect(span.tags).to include(
        Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => producer.id,
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 3,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => 'other_topic,topic_name',
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => '0,1'
      )
    end
  end

  describe '#produce_many_async' do
    it 'traces a producer job' do
      messages = [
        {topic: 'topic_name', payload: 'foo', partition: 1},
        {topic: 'topic_name', payload: 'bar'},
        {topic: 'other_topic', payload: 'baz', partition: 0},
      ].shuffle
      producer.produce_many_async(messages)

      expect(span.name).to eq('karafka.produce')
      expect(span.resource).to eq('waterdrop.produce_many_async')
      expect(span.tags).to include(
        Datadog::Tracing::Contrib::WaterDrop::Ext::TAG_PRODUCER => producer.id,
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_MESSAGE_COUNT => 3,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_SYSTEM => Datadog::Tracing::Contrib::Karafka::Ext::TAG_SYSTEM,
        Datadog::Tracing::Contrib::Ext::Messaging::TAG_DESTINATION => 'other_topic,topic_name',
        Datadog::Tracing::Contrib::Karafka::Ext::TAG_PARTITION => '0,1'
      )
    end
  end
end
