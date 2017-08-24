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
          @tracer = enable_tracer
          client = ::Aws::S3::Client.new(stub_responses: true)
          client.list_buckets

          @span = @tracer.writer.spans.find { |span| span.resource == RESOURCE }
        end

        def test_span_name
          assert_equal('s3.list_buckets', @span.name)
        end

        def test_span_service
          assert_equal(pin.service, @span.service)
        end

        def test_span_type
          assert_equal(pin.app_type, @span.span_type)
        end

        def test_span_resource
          assert_equal('aws.command', @span.resource)
        end

        def test_span_tags
          assert_equal('aws-sdk-ruby', @span.get_tag('aws.agent'))
          assert_equal('list_buckets', @span.get_tag('aws.operation'))
          assert_equal('us-stubbed-1', @span.get_tag('aws.region'))
          assert_equal('/', @span.get_tag('path'))
          assert_equal('s3.us-stubbed-1.amazonaws.com', @span.get_tag('host'))
          assert_equal('GET', @span.get_tag(Datadog::Ext::HTTP::METHOD))
          assert_equal('200', @span.get_tag(Datadog::Ext::HTTP::STATUS_CODE))
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
      end
    end
  end
end
