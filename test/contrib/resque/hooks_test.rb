require 'helper'
require 'resque'
require 'ddtrace'
require_relative 'test_helper'

module Datadog
  module Contrib
    module Resque
      class HooksTest < Minitest::Test
        REDIS_HOST = '127.0.0.1'.freeze()
        REDIS_PORT = 46379

        def setup
          redis_url = "redis://#{REDIS_HOST}:#{REDIS_PORT}"

          ::Resque.redis = redis_url
          @tracer = enable_test_tracer!
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

        def test_failed_job
          begin
            perform_job(TestJob, false)
          rescue StandardError => e
            error = e
          end
          spans = @tracer.writer.spans
          span = spans.first

          assert_equal('TestJob failed', error.message, 'unplanned error occured')
          assert_equal(1, spans.length, 'created wrong number of spans')
          assert_equal('resque.job', span.name, 'wrong span name set')
          assert_equal(TestJob.name, span.resource, 'span resource should match job name')
          assert_equal(Ext::AppTypes::WORKER, span.span_type, 'span should be of worker span type')
          assert_equal('resque', span.service, 'wrong service stored in span')
          assert_equal(error.message, span.get_tag(Ext::Errors::MSG), 'wrong error message populated')
          assert_equal(Ext::Errors::STATUS, span.status, 'wrong status in span')
          assert_equal('StandardError', span.get_tag(Ext::Errors::TYPE), 'wrong type of error stored in span')
        end

        def enable_test_tracer!
          get_test_tracer.tap { |tracer| pin.tracer = tracer }
        end

        def pin
          TestJob.datadog_pin
        end
      end
    end
  end
end
