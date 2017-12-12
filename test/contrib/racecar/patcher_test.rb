require 'helper'
require 'racecar'
require 'racecar/cli'
require 'active_support'
require 'ddtrace'
require_relative 'dummy_consumer'
require_relative 'dummy_batch_consumer'

module Datadog
  module Contrib
    module Racecar
      class PatcherTest < Minitest::Test
        def setup
          Datadog.configure do |c|
            c.use :racecar, tracer: get_test_tracer
          end

          @tracer = Datadog.configuration[:racecar][:tracer]
        end

        #
        # Single message consumer
        #
        def test_process_success
          # Emulate consumer success
          processor = DummyConsumer.new
          topic = 'dd_trace_test_dummy'
          payload = {
            consumer_class: processor.to_s,
            topic: topic,
            partition: 1,
            offset: 2,
          }

          ActiveSupport::Notifications.instrument("start_process_message.racecar", payload)
          ActiveSupport::Notifications.instrument("process_message.racecar", payload)

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.first.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            # assert_equal('DummyConsumer', span.resource) # TODO: Update name
            assert_equal(topic, span.get_tag('kafka.topic'))
            # assert_equal('DummyConsumer', span.get_tag('kafka.consumer'))
            assert_equal("1", span.get_tag('kafka.partition'))
            assert_equal("2", span.get_tag('kafka.offset'))
            assert_nil(span.get_tag('kafka.first_offset'))
            refute_equal(Ext::Errors::STATUS, span.status)
          end
        end

        def test_process_failure
          # Emulate consumer failure
          processor = DummyConsumer.new
          topic = 'dd_trace_test_dummy'
          payload = {
            consumer_class: processor.to_s,
            topic: topic,
            partition: 1,
            offset: 2,
          }

          ActiveSupport::Notifications.instrument("start_process_message.racecar", payload)
          begin
            raise ArgumentError.new('This message was destined to fail.')
          rescue ArgumentError => e
            payload.merge!(exception_object: e)
          end
          ActiveSupport::Notifications.instrument("process_message.racecar", payload)

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.last.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            # assert_equal('DummyConsumer', span.resource) # TODO: Update name
            assert_equal(topic, span.get_tag('kafka.topic'))
            # assert_equal('DummyConsumer', span.get_tag('kafka.consumer'))
            assert_equal("1", span.get_tag('kafka.partition'))
            assert_equal("2", span.get_tag('kafka.offset'))
            assert_nil(span.get_tag('kafka.first_offset'))
            assert_equal(Ext::Errors::STATUS, span.status)
          end
        end

        #
        # Batch message consumer
        #
        def test_process_batch_success
          # Emulate consumer success
          processor = DummyBatchConsumer.new
          topic = 'dd_trace_test_dummy_batch'
          payload = {
            consumer_class: processor.to_s,
            topic: topic,
            partition: 1,
            first_offset: 2,
          }

          ActiveSupport::Notifications.instrument("start_process_batch.racecar", payload)
          ActiveSupport::Notifications.instrument("process_batch.racecar", payload)

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.first.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            # assert_equal('DummyBatchConsumer', span.resource) # TODO: Update name
            assert_equal(topic, span.get_tag('kafka.topic'))
            # assert_equal('DummyBatchConsumer', span.get_tag('kafka.consumer'))
            assert_equal("1", span.get_tag('kafka.partition'))
            assert_nil(span.get_tag('kafka.offset'))
            assert_equal("2", span.get_tag('kafka.first_offset'))
            refute_equal(Ext::Errors::STATUS, span.status)
          end
        end

        def test_process_batch_failure
          # Emulate consumer failure
          processor = DummyBatchConsumer.new
          topic = 'dd_trace_test_dummy_batch'
          payload = {
            consumer_class: processor.to_s,
            topic: topic,
            partition: 1,
            first_offset: 2,
          }

          ActiveSupport::Notifications.instrument("start_process_batch.racecar", payload)
          begin
            raise ArgumentError.new('This message was destined to fail.')
          rescue ArgumentError => e
            payload.merge!(exception_object: e)
          end
          ActiveSupport::Notifications.instrument("process_batch.racecar", payload)

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.last.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            # assert_equal('DummyBatchConsumer', span.resource) # TODO: Update name
            assert_equal(topic, span.get_tag('kafka.topic'))
            # assert_equal('DummyBatchConsumer', span.get_tag('kafka.consumer'))
            assert_equal("1", span.get_tag('kafka.partition'))
            assert_nil(span.get_tag('kafka.offset'))
            assert_equal("2", span.get_tag('kafka.first_offset'))
            assert_equal(Ext::Errors::STATUS, span.status)
          end
        end

        private

        attr_reader :tracer

        def deliver_message(value, opts = {})
          kafka_client.deliver_message(value, topic: opts[:topic])
        end

        def create_and_start_racecar_thread(consumer_class)
          ::Racecar.config.tap do |c|
            c.client_id = kafka_client_id
            c.brokers = kafka_brokers
          end

          Thread.new do
            ::Racecar::Cli.main([consumer_class.name])
          end
        end

        def kafka_client
          @kafka_client ||= Kafka.new(
            seed_brokers: ["localhost:29092"],
            client_id: kafka_client_id
          )
        end

        def kafka_client_id
          'dd_trace_test'
        end

        def kafka_brokers
          # TODO: Update for CI friendliness
          # ENV['TEST_KAFKA_PORT']
          ["localhost:29092"]
        end

        def all_spans
          tracer.writer.spans(:keep)
        end
      end
    end
  end
end
