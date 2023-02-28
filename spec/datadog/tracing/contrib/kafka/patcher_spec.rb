require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'ruby-kafka'
require 'active_support'
require 'ddtrace'

RSpec.describe 'Kafka patcher' do
  let(:configuration_options) { {} }
  let(:client_id) { SecureRandom.uuid }
  let(:span) do
    spans.find { |s| s.name == span_name }
  end

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

  describe 'connection.request' do
    let(:api) { 'api' }
    let(:request_size) { rand(1..1000) }
    let(:response_size) { rand(1..1000) }
    let(:payload) do
      {
        client_id: client_id,
        api: api,
        request_size: request_size,
        response_size: response_size
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_CONNECTION_REQUEST }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('request.connection.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.connection.request')
          expect(span.resource).to eq(api)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.request_size')).to eq(request_size)
          expect(span.get_tag('kafka.response_size')).to eq(response_size)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('connection.request')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('request.connection.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.connection.request')
          expect(span.resource).to eq(api)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.request_size')).to eq(request_size)
          expect(span.get_tag('kafka.response_size')).to eq(response_size)
          expect(span).to have_error
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('request.connection.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('request.connection.kafka', payload) }
    end
  end

  describe 'consumer.process_batch' do
    let(:group_id) { SecureRandom.uuid }
    let(:topic) { 'my-topic' }
    let(:message_count) { rand(1..10) }
    let(:partition) { rand(0..100) }
    let(:highwater_mark_offset) { rand(100..1000) }
    let(:offset_lag) { rand(1..1000) }
    let(:payload) do
      {
        client_id: client_id,
        group_id: group_id,
        topic: topic,
        message_count: message_count,
        partition: partition,
        highwater_mark_offset: highwater_mark_offset,
        offset_lag: offset_lag
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_PROCESS_BATCH }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process_batch.consumer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.process_batch')
          expect(span.resource).to eq(topic)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.highwater_mark_offset')).to eq(highwater_mark_offset)
          expect(span.get_tag('kafka.offset_lag')).to eq(offset_lag)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consumer.process_batch')
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('process_batch.consumer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.process_batch')
          expect(span.resource).to eq(topic)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.highwater_mark_offset')).to eq(highwater_mark_offset)
          expect(span.get_tag('kafka.offset_lag')).to eq(offset_lag)
          expect(span).to have_error
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('process_batch.consumer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('process_batch.consumer.kafka', payload) }
    end
  end

  describe 'consumer.process_message' do
    let(:group_id) { SecureRandom.uuid }
    let(:topic) { 'my-topic' }
    let(:key) { SecureRandom.hex }
    let(:partition) { rand(0..100) }
    let(:offset) { rand(1..1000) }
    let(:offset_lag) { rand(1..1000) }
    let(:payload) do
      {
        client_id: client_id,
        group_id: group_id,
        key: key,
        topic: topic,
        partition: partition,
        offset: offset,
        offset_lag: offset_lag
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_PROCESS_MESSAGE }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process_message.consumer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.process_message')
          expect(span.resource).to eq(topic)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.message_key')).to eq(key)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.offset')).to eq(offset)
          expect(span.get_tag('kafka.offset_lag')).to eq(offset_lag)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consumer.process_message')
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('process_message.consumer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.process_message')
          expect(span.resource).to eq(topic)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span.get_tag('kafka.topic')).to eq(topic)
          expect(span.get_tag('kafka.message_key')).to eq(key)
          expect(span.get_tag('kafka.partition')).to eq(partition)
          expect(span.get_tag('kafka.offset')).to eq(offset)
          expect(span.get_tag('kafka.offset_lag')).to eq(offset_lag)
          expect(span).to have_error
          expect(span.get_tag('span.kind')).to eq('consumer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('process_message.consumer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('process_message.consumer.kafka', payload) }
    end
  end

  describe 'consumer.heartbeat' do
    let(:group_id) { SecureRandom.uuid }
    let(:topic_partitions) do
      {
        'foo' => [0, 2],
        'bar' => [1, 3]
      }
    end
    let(:payload) do
      {
        client_id: client_id,
        group_id: group_id,
        topic_partitions: topic_partitions
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_CONSUMER_HEARTBEAT }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('heartbeat.consumer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.heartbeat')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span.get_tag('kafka.topic_partitions.foo')).to eq(topic_partitions['foo'].to_s)
          expect(span.get_tag('kafka.topic_partitions.bar')).to eq(topic_partitions['bar'].to_s)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consumer.heartbeat')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('heartbeat.consumer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.heartbeat')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span.get_tag('kafka.topic_partitions.foo')).to eq(topic_partitions['foo'].to_s)
          expect(span.get_tag('kafka.topic_partitions.bar')).to eq(topic_partitions['bar'].to_s)
          expect(span).to have_error
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('heartbeat.consumer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('heartbeat.consumer.kafka', payload) }
    end
  end

  describe 'consumer.join_group' do
    let(:group_id) { SecureRandom.uuid }
    let(:payload) do
      {
        client_id: client_id,
        group_id: group_id
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_CONSUMER_JOIN_GROUP }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('join_group.consumer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.join_group')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consumer.join_group')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('join_group.consumer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.join_group')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span).to have_error
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('join_group.consumer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('join_group.consumer.kafka', payload) }
    end
  end

  describe 'consumer.leave_group' do
    let(:group_id) { SecureRandom.uuid }
    let(:payload) do
      {
        client_id: client_id,
        group_id: group_id
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_CONSUMER_LEAVE_GROUP }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('leave_group.consumer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.leave_group')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consumer.leave_group')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('leave_group.consumer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.leave_group')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span).to have_error
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('leave_group.consumer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('leave_group.consumer.kafka', payload) }
    end
  end

  describe 'consumer.sync_group' do
    let(:group_id) { SecureRandom.uuid }
    let(:payload) do
      {
        client_id: client_id,
        group_id: group_id
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_CONSUMER_SYNC_GROUP }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('sync_group.consumer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.sync_group')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('consumer.sync_group')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('sync_group.consumer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.consumer.sync_group')
          expect(span.resource).to eq(group_id)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.group')).to eq(group_id)
          expect(span).to have_error
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('sync_group.consumer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('sync_group.consumer.kafka', payload) }
    end
  end

  describe 'producer.send_messages' do
    let(:message_count) { rand(10..100) }
    let(:sent_message_count) { rand(1..message_count) }
    let(:payload) do
      {
        client_id: client_id,
        message_count: message_count,
        sent_message_count: sent_message_count
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_SEND_MESSAGES }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('send_messages.producer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.producer.send_messages')
          expect(span.resource).to eq(span.name)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span.get_tag('kafka.sent_message_count')).to eq(sent_message_count)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('producer.send_messages')
          expect(span.get_tag('span.kind')).to eq('producer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('send_messages.producer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.producer.send_messages')
          expect(span.resource).to eq(span.name)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span.get_tag('kafka.sent_message_count')).to eq(sent_message_count)
          expect(span).to have_error
          expect(span.get_tag('span.kind')).to eq('producer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('send_messages.producer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('send_messages.producer.kafka', payload) }
    end
  end

  describe 'producer.deliver_messages' do
    let(:attempts) { rand(1..10) }
    let(:message_count) { rand(10..100) }
    let(:delivered_message_count) { rand(1..message_count) }
    let(:payload) do
      {
        client_id: client_id,
        attempts: attempts,
        message_count: message_count,
        delivered_message_count: delivered_message_count
      }
    end
    let(:span_name) { Datadog::Tracing::Contrib::Kafka::Ext::SPAN_DELIVER_MESSAGES }

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('deliver_messages.producer.kafka', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.producer.deliver_messages')
          expect(span.resource).to eq(span.name)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.attempts')).to eq(attempts)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span.get_tag('kafka.delivered_message_count')).to eq(delivered_message_count)
          expect(span).to_not have_error
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('kafka')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('producer.deliver_messages')
          expect(span.get_tag('span.kind')).to eq('producer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('deliver_messages.producer.kafka', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq(tracer.default_service)
          expect(span.name).to eq('kafka.producer.deliver_messages')
          expect(span.resource).to eq(span.name)
          expect(span.get_tag('kafka.client')).to eq(client_id)
          expect(span.get_tag('kafka.attempts')).to eq(attempts)
          expect(span.get_tag('kafka.message_count')).to eq(message_count)
          expect(span.get_tag('kafka.delivered_message_count')).to eq(delivered_message_count)
          expect(span).to have_error
          expect(span.get_tag('span.kind')).to eq('producer')
          expect(span.get_tag('messaging.system')).to eq('kafka')
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('deliver_messages.producer.kafka', payload) }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Kafka::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true do
      before { ActiveSupport::Notifications.instrument('deliver_messages.producer.kafka', payload) }
    end
  end
end
