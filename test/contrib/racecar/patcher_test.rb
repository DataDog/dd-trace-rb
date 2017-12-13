require 'helper'
require 'racecar'
require 'racecar/cli'
require 'active_support'
require 'ddtrace'

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
          topic = 'dd_trace_test_dummy'
          consumer = 'DummyConsumer'
          partition = 1
          offset = 2
          payload = {
            consumer_class: consumer,
            topic: topic,
            partition: partition,
            offset: offset
          }

          ActiveSupport::Notifications.instrument('start_process_message.racecar', payload)
          ActiveSupport::Notifications.instrument('process_message.racecar', payload)

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.first.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            assert_equal(consumer, span.resource)
            assert_equal(topic, span.get_tag('kafka.topic'))
            assert_equal(consumer, span.get_tag('kafka.consumer'))
            assert_equal(partition.to_s, span.get_tag('kafka.partition'))
            assert_equal(offset.to_s, span.get_tag('kafka.offset'))
            assert_nil(span.get_tag('kafka.first_offset'))
            refute_equal(Ext::Errors::STATUS, span.status)
          end
        end

        def test_process_failure
          # Emulate consumer failure
          topic = 'dd_trace_test_dummy'
          consumer = 'DummyConsumer'
          partition = 1
          offset = 2
          payload = {
            consumer_class: consumer,
            topic: topic,
            partition: partition,
            offset: offset
          }

          ActiveSupport::Notifications.instrument('start_process_message.racecar', payload)
          begin
            ActiveSupport::Notifications.instrument('process_message.racecar', payload) do
              raise ConsumerFailureTestError
            end
          rescue ConsumerFailureTestError
            nil
          end

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.last.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            assert_equal(consumer, span.resource)
            assert_equal(topic, span.get_tag('kafka.topic'))
            assert_equal(consumer, span.get_tag('kafka.consumer'))
            assert_equal(partition.to_s, span.get_tag('kafka.partition'))
            assert_equal(offset.to_s, span.get_tag('kafka.offset'))
            assert_nil(span.get_tag('kafka.first_offset'))
            assert_equal(Ext::Errors::STATUS, span.status)
          end
        end

        #
        # Batch message consumer
        #
        def test_process_batch_success
          # Emulate consumer success
          topic = 'dd_trace_test_dummy_batch'
          consumer = 'DummyBatchConsumer'
          partition = 1
          offset = 2
          payload = {
            consumer_class: consumer,
            topic: topic,
            partition: partition,
            first_offset: offset
          }

          ActiveSupport::Notifications.instrument('start_process_batch.racecar', payload)
          ActiveSupport::Notifications.instrument('process_batch.racecar', payload)

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.first.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            assert_equal(consumer, span.resource)
            assert_equal(topic, span.get_tag('kafka.topic'))
            assert_equal(consumer, span.get_tag('kafka.consumer'))
            assert_equal(partition.to_s, span.get_tag('kafka.partition'))
            assert_nil(span.get_tag('kafka.offset'))
            assert_equal(offset.to_s, span.get_tag('kafka.first_offset'))
            refute_equal(Ext::Errors::STATUS, span.status)
          end
        end

        def test_process_batch_failure
          # Emulate consumer failure
          topic = 'dd_trace_test_dummy_batch'
          consumer = 'DummyBatchConsumer'
          partition = 1
          offset = 2
          payload = {
            consumer_class: consumer,
            topic: topic,
            partition: partition,
            first_offset: offset
          }

          ActiveSupport::Notifications.instrument('start_process_batch.racecar', payload)
          begin
            ActiveSupport::Notifications.instrument('process_batch.racecar', payload) do
              raise ConsumerFailureTestError
            end
          rescue ConsumerFailureTestError
            nil
          end

          # Assert correct output
          spans = all_spans.select { |s| s.name == Patcher::NAME }
          assert_equal(1, spans.length)

          spans.first.tap do |span|
            assert_equal('racecar', span.service)
            assert_equal('racecar.consumer', span.name)
            assert_equal(consumer, span.resource)
            assert_equal(topic, span.get_tag('kafka.topic'))
            assert_equal(consumer, span.get_tag('kafka.consumer'))
            assert_equal(partition.to_s, span.get_tag('kafka.partition'))
            assert_nil(span.get_tag('kafka.offset'))
            assert_equal(offset.to_s, span.get_tag('kafka.first_offset'))
            assert_equal(Ext::Errors::STATUS, span.status)
          end
        end

        private

        attr_reader :tracer

        def all_spans
          tracer.writer.spans(:keep)
        end

        class ConsumerFailureTestError < StandardError
        end
      end
    end
  end
end
