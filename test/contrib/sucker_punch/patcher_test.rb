require 'helper'
require 'sucker_punch'
require 'ddtrace'
require_relative 'dummy_worker'

module Datadog
  module Contrib
    module SuckerPunch
      class PatcherTest < Minitest::Test
        include TestTracerHelper
        def integration_name
          :sucker_punch
        end

        def configure
          Datadog.configure do |c|
            c.use :sucker_punch
          end

          ::SuckerPunch::Queue.clear
          ::SuckerPunch::RUNNING.make_true
        end

        def test_two_spans_per_job
          # One span when pushing to the queue
          # One span for the job execution itself
          ::DummyWorker.perform_async
          try_wait_until { fetch_spans.length == 2 }
          assert_equal(2, spans.length)
        end

        def test_successful_job
          ::DummyWorker.perform_async
          try_wait_until { fetch_spans.length == 2 }

          span = spans.find { |s| s.resource[/PROCESS/] }
          assert_equal('sucker_punch', span.service)
          assert_equal('sucker_punch.perform', span.name)
          assert_equal('PROCESS DummyWorker', span.resource)
          assert_equal('DummyWorker', span.get_tag('sucker_punch.queue'))
          refute_equal(Datadog::Ext::Errors::STATUS, span.status)
          assert_equal(span.get_metric('_dd.measured'), 1.0)
        end

        def test_failed_job
          ::DummyWorker.perform_async(:fail)
          try_wait_until { fetch_spans.length == 2 }

          span = spans.find { |s| s.resource[/PROCESS/] }
          assert_equal('sucker_punch', span.service)
          assert_equal('sucker_punch.perform', span.name)
          assert_equal('PROCESS DummyWorker', span.resource)
          assert_equal('DummyWorker', span.get_tag('sucker_punch.queue'))
          assert_equal(Datadog::Ext::Errors::STATUS, span.status)
          assert_equal('ZeroDivisionError', span.get_tag(Datadog::Ext::Errors::TYPE))
          assert_equal('divided by 0', span.get_tag(Datadog::Ext::Errors::MSG))
          assert_equal(span.get_metric('_dd.measured'), 1.0)
        end

        def test_async_enqueueing
          ::DummyWorker.perform_async
          try_wait_until { fetch_spans.any? }

          span = spans.find { |s| s.resource[/ENQUEUE/] }
          assert_equal('sucker_punch', span.service)
          assert_equal('sucker_punch.perform_async', span.name)
          assert_equal('ENQUEUE DummyWorker', span.resource)
          assert_equal('DummyWorker', span.get_tag('sucker_punch.queue'))
          assert_equal(span.get_metric('_dd.measured'), 1.0)
        end

        def test_delayed_enqueueing
          ::DummyWorker.perform_in(0)
          try_wait_until { fetch_spans.any? }

          span = spans.find { |s| s.resource[/ENQUEUE/] }
          assert_equal('sucker_punch', span.service)
          assert_equal('sucker_punch.perform_in', span.name)
          assert_equal('ENQUEUE DummyWorker', span.resource)
          assert_equal('DummyWorker', span.get_tag('sucker_punch.queue'))
          assert_equal(0, span.get_tag('sucker_punch.perform_in'))
          assert_equal(span.get_metric('_dd.measured'), 1.0)
        end

        private

        def pin
          ::SuckerPunch.datadog_pin
        end
      end
    end
  end
end
