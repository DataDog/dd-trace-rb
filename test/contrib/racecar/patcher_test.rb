require 'helper'
require 'racecar'
require 'racecar/cli'
require 'ddtrace'
require_relative 'dummy_consumer'
require_relative 'dummy_batch_consumer'

module Datadog
  module Contrib
    module Racecar
      class PatcherTest < Minitest::Test
        def setup
          Monkey.patch_module(:racecar)

          @tracer = enable_test_tracer!
        end

        #
        # Single message consumer
        #
        def test_process_successful
          (1..3).each { |n| deliver_message(n.to_s, topic: 'dd_trace_test_dummy') }

          racecar_thread = create_and_start_racecar_thread(DummyConsumer)

          try_wait_until(backoff: 0.3) { all_spans.length == 3 }

          racecar_thread.join(1)

          span = all_spans.find { |s| s.name == NAME }

          assert_equal('racecar', span.service)
          assert_equal('racecar.consumer', span.name)
          # assert_equal('DummyConsumer', span.resource) # TODO: Update name
          assert_equal('dd_trace_test_dummy', span.get_tag('kafka.topic'))
          # assert_equal('DummyConsumer', span.get_tag('kafka.consumer'))
          assert_kind(Integer, span.get_tag('kafka.partition'))
          assert_kind(Integer, span.get_tag('kafka.offset'))
          assert_nil(span.get_tag('kafka.first_offset'))
          refute_equal(Ext::Errors::STATUS, span.status)
        end

        # def test_failed_job
        #   ::DummyConsumer.perform_async(:fail)
        #   try_wait_until { all_spans.length == 2 }

        #   span = all_spans.find { |s| s.resource[/PROCESS/] }
        #   assert_equal('racecar', span.service)
        #   assert_equal('racecar.perform', span.name)
        #   assert_equal('PROCESS DummyConsumer', span.resource)
        #   assert_equal('DummyConsumer', span.get_tag('racecar.queue'))
        #   assert_equal(Ext::Errors::STATUS, span.status)
        #   assert_equal('ZeroDivisionError', span.get_tag(Ext::Errors::TYPE))
        #   assert_equal('divided by 0', span.get_tag(Ext::Errors::MSG))
        # end

        # def test_async_enqueueing
        #   ::DummyConsumer.perform_async
        #   try_wait_until { all_spans.any? }

        #   span = all_spans.find { |s| s.resource[/ENQUEUE/] }
        #   assert_equal('racecar', span.service)
        #   assert_equal('racecar.perform_async', span.name)
        #   assert_equal('ENQUEUE DummyConsumer', span.resource)
        #   assert_equal('DummyConsumer', span.get_tag('racecar.queue'))
        # end

        # def test_delayed_enqueueing
        #   ::DummyConsumer.perform_in(0)
        #   try_wait_until { all_spans.any? }

        #   span = all_spans.find { |s| s.resource[/ENQUEUE/] }
        #   assert_equal('racecar', span.service)
        #   assert_equal('racecar.perform_in', span.name)
        #   assert_equal('ENQUEUE DummyConsumer', span.resource)
        #   assert_equal('DummyConsumer', span.get_tag('racecar.queue'))
        #   assert_equal('0', span.get_tag('racecar.perform_in'))
        # end

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

        def enable_test_tracer!
          get_test_tracer.tap do |tracer|
            Datadog.configuration[:racecar][:tracer] = tracer
          end
        end
      end
    end
  end
end
