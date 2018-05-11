require 'helper'
require 'resque'
require 'ddtrace'
require_relative 'test_helper'

module Datadog
  module Contrib
    module Resque
      class HooksTest < Minitest::Test
        REDIS_HOST = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1').freeze
        REDIS_PORT = ENV.fetch('TEST_REDIS_PORT', 6379)

        def setup
          Datadog.configure do |c|
            c.use :resque
          end

          redis_url = "redis://#{REDIS_HOST}:#{REDIS_PORT}"
          ::Resque.redis = redis_url
          @tracer = enable_test_tracer!
          ::Resque::Failure.clear
        end

        def test_successful_job
          perform_job(TestJob)
          spans = @tracer.writer.spans
          span = spans.first

          assert_equal(1, spans.length, 'created wrong number of spans')
          assert_equal('resque.job', span.name, 'wrong span name set')
          assert_equal(TestJob.name, span.resource, 'span resource should match job name')
          assert_equal(Ext::AppTypes::WORKER, span.span_type, 'span should be of worker span type')
          assert_equal('resque', span.service, 'wrong service stored in span')
          refute_equal(Ext::Errors::STATUS, span.status, 'wrong span status')
        end

        def test_clean_state
          @tracer.trace('main.process') do
            perform_job(TestCleanStateJob, @tracer)
          end

          spans = @tracer.writer.spans
          assert_equal(2, spans.length)
          assert_equal(0, ::Resque::Failure.count)

          main_span = spans[0]
          job_span = spans[1]
          assert_equal('main.process', main_span.name, 'wrong span name set')
          assert_equal('resque.job', job_span.name, 'wrong span name set')
          refute_equal(main_span.trace_id, job_span.trace_id, 'main process and resque job must not be in the same trace')
        end

        def test_service_change
          pin = Datadog::Pin.get_from(::Resque)
          pin.service = 'test_service_change'
          perform_job(TestJob)
          spans = @tracer.writer.spans
          span = spans.first

          pin.service = 'resque' # reset pin
          assert_equal(1, spans.length, 'created wrong number of spans')
          assert_equal('resque.job', span.name, 'wrong span name set')
          assert_equal(TestJob.name, span.resource, 'span resource should match job name')
          assert_equal(Ext::AppTypes::WORKER, span.span_type, 'span should be of worker span type')
          assert_equal('test_service_change', span.service, 'wrong service stored in span')
          refute_equal(Ext::Errors::STATUS, span.status, 'wrong span status')
        end

        def test_failed_job
          perform_job(TestJob, false)
          spans = @tracer.writer.spans
          span = spans.first

          # retrieve error from Resque backend
          assert_equal(1, ::Resque::Failure.count)
          error_message = ::Resque::Failure.all['error']

          assert_equal('TestJob failed', error_message, 'unplanned error occured')
          assert_equal(1, spans.length, 'created wrong number of spans')
          assert_equal('resque.job', span.name, 'wrong span name set')
          assert_equal(TestJob.name, span.resource, 'span resource should match job name')
          assert_equal(Ext::AppTypes::WORKER, span.span_type, 'span should be of worker span type')
          assert_equal('resque', span.service, 'wrong service stored in span')
          assert_equal(error_message, span.get_tag(Ext::Errors::MSG), 'wrong error message populated')
          assert_equal(Ext::Errors::STATUS, span.status, 'wrong status in span')
          assert_equal('StandardError', span.get_tag(Ext::Errors::TYPE), 'wrong type of error stored in span')
        end

        def test_workers_patch
          worker_class1 = Class.new
          worker_class2 = Class.new

          remove_patch!(:resque)

          Datadog.configure do |c|
            c.use(:resque, workers: [worker_class1, worker_class2])
          end

          assert_includes(worker_class1.singleton_class.included_modules, ResqueJob)
          assert_includes(worker_class2.singleton_class.included_modules, ResqueJob)
        end

        def enable_test_tracer!
          get_test_tracer.tap { |tracer| pin.tracer = tracer }
        end

        def pin
          ::Resque.datadog_pin
        end
      end
    end
  end
end
