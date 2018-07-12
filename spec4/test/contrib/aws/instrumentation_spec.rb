require('helper')
require('aws-sdk')
require('ddtrace')
require('ddtrace/contrib/aws/patcher')
require('ddtrace/ext/http')
module Datadog
  module Contrib
    module Aws
      class InstrumentationTest < Minitest::Test
        before do
          @tracer = enable_tracer
          @client = ::Aws::S3::Client.new(stub_responses: true)
        end
        it('pin defaults') do
          expect(pin.service).to(eq('aws'))
          expect(pin.app_type).to(eq('web'))
          expect(pin.app).to(eq('aws'))
          expect(pin.name).to(be_nil)
          expect(pin.config).to(be_nil)
        end
        it('list buckets') do
          @client.list_buckets
          try_wait_until { all_spans.any? }
          expect(all_spans.length).to(eq(1))
          aws_span = all_spans[0]
          expect(aws_span.name).to(eq('aws.command'))
          expect(aws_span.service).to(eq('aws'))
          expect(aws_span.span_type).to(eq('web'))
          expect(aws_span.resource).to(eq('s3.list_buckets'))
          expect(aws_span.get_tag('aws.agent')).to(eq('aws-sdk-ruby'))
          expect(aws_span.get_tag('aws.operation')).to(eq('list_buckets'))
          expect(aws_span.get_tag('aws.region')).to(eq('us-stubbed-1'))
          expect(aws_span.get_tag('path')).to(eq('/'))
          expect(aws_span.get_tag('host')).to(eq('s3.us-stubbed-1.amazonaws.com'))
          expect(aws_span.get_tag('http.method')).to(eq('GET'))
          expect(aws_span.get_tag('http.status_code')).to(eq('200'))
        end
        it('client response') do
          client = ::Aws::S3::Client.new(stub_responses: { list_buckets: { buckets: [{ name: 'bucket1' }] } })
          buckets = client.list_buckets.buckets.map(&:name)
          expect(buckets).to(eq(['bucket1']))
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
