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
        # NOTE: This test is not repeatable without clearing your Kafka topic,
        #       because old failed messages will remain in the partition and
        #       fail the next test run.
        #       Needs to be reworked.
        def test_process 
          deliver_message('pass', topic: 'dd_trace_test_dummy')
          deliver_message('fail', topic: 'dd_trace_test_dummy')

          racecar_thread = create_and_start_racecar_thread(DummyConsumer)

          try_wait_until(backoff: 0.5) { all_spans.length == 2 }

          racecar_thread.join(0.5)
          racecar_thread.kill

          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(2, spans.length)

          spans.first.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            # assert_equal('DummyConsumer', span.resource) # TODO: Update name
            assert_equal('dd_trace_test_dummy', span.get_tag('kafka.topic'))
            # assert_equal('DummyConsumer', span.get_tag('kafka.consumer'))
            assert_match(/[0-9]+/, span.get_tag('kafka.partition'))
            assert_match(/[0-9]+/, span.get_tag('kafka.offset'))
            assert_nil(span.get_tag('kafka.first_offset'))
            refute_equal(Ext::Errors::STATUS, span.status)
          end

          spans.last.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            # assert_equal('DummyConsumer', span.resource) # TODO: Update name
            assert_equal('dd_trace_test_dummy', span.get_tag('kafka.topic'))
            # assert_equal('DummyConsumer', span.get_tag('kafka.consumer'))
            assert_match(/[0-9]+/, span.get_tag('kafka.partition'))
            assert_match(/[0-9]+/, span.get_tag('kafka.offset'))
            assert_nil(span.get_tag('kafka.first_offset'))
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
