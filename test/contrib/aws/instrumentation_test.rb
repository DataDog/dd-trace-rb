require 'helper'
require 'aws-sdk'
require 'ddtrace'
require 'ddtrace/contrib/aws/patcher'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    module Aws
      class InstrumentationTest < Minitest::Test
        def setup
          # initializes the tracer and a stub client
          @tracer = enable_tracer
          @client = ::Aws::S3::Client.new(stub_responses: true)
        end

        def test_pin_defaults
          assert_equal('aws', pin.service)
          assert_equal('web', pin.app_type)
          assert_equal('aws', pin.app)
          assert_nil(pin.name)
          assert_nil(pin.config)
        end

        def test_list_buckets
          @client.list_buckets
          try_wait_until { all_spans.any? }
          assert_equal(1, all_spans.length)
          aws_span = all_spans[0]

          # check Span attributes
          assert_equal('s3.list_buckets', aws_span.name)
          assert_equal('aws', aws_span.service)
          assert_equal('web', aws_span.span_type)
          assert_equal('aws.command', aws_span.resource)
          # check Span tags
          assert_equal('aws-sdk-ruby', aws_span.get_tag('aws.agent'))
          assert_equal('list_buckets', aws_span.get_tag('aws.operation'))
          assert_equal('us-stubbed-1', aws_span.get_tag('aws.region'))
          assert_equal('/', aws_span.get_tag('path'))
          assert_equal('s3.us-stubbed-1.amazonaws.com', aws_span.get_tag('host'))
          assert_equal('GET', aws_span.get_tag('http.method'))
          assert_equal('200', aws_span.get_tag('http.status_code'))
        end

        def test_client_response
          client = ::Aws::S3::Client.new(
            stub_responses: { list_buckets: { buckets: [{ name: 'bucket1' }] } }
          )

          buckets = client.list_buckets.buckets.map(&:name)
          assert_equal(['bucket1'], buckets)
        end

        private

        def enable_tracer
          Patcher.patch
          get_test_tracer.tap { |tracer| pin.tracer = tracer }
        end

        def pin
          ::Aws.datadog_pin
        end

        def all_spans
          @tracer.writer.spans(:keep)
        end
      end
    end
  end
end
