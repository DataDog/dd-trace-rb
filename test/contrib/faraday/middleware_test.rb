require 'helper'
require 'ddtrace'
require 'faraday'
require 'ddtrace/ext/distributed'

module Datadog
  module Contrib
    module Faraday
      class MiddlewareTest < Minitest::Test
        Monkey.patch_module(:faraday)

        def setup
          ::Faraday.datadog_pin.tracer = get_test_tracer
        end

        def teardown
          Datadog.configuration[:faraday].reset_options!
        end

        def test_no_interference
          response = client.get('/success')

          assert_kind_of(::Faraday::Response, response)
          assert_equal(response.body, 'OK')
          assert_equal(response.status, 200)
        end

        def test_successful_request
          client.get('/success')
          span = request_span

          assert_equal(SERVICE, span.service)
          assert_equal(NAME, span.name)
          assert_equal('GET', span.resource)
          assert_equal('GET', span.get_tag(Ext::HTTP::METHOD))
          assert_equal('200', span.get_tag(Ext::HTTP::STATUS_CODE))
          assert_equal('/success', span.get_tag(Ext::HTTP::URL))
          assert_equal('example.com', span.get_tag(Ext::NET::TARGET_HOST))
          assert_equal('80', span.get_tag(Ext::NET::TARGET_PORT))
          assert_equal(Ext::HTTP::TYPE, span.span_type)
          refute_equal(Ext::Errors::STATUS, span.status)
        end

        def test_error_response
          client.post('/failure')
          span = request_span

          assert_equal(SERVICE, span.service)
          assert_equal(NAME, span.name)
          assert_equal('POST', span.resource)
          assert_equal('POST', span.get_tag(Ext::HTTP::METHOD))
          assert_equal('/failure', span.get_tag(Ext::HTTP::URL))
          assert_equal('500', span.get_tag(Ext::HTTP::STATUS_CODE))
          assert_equal('example.com', span.get_tag(Ext::NET::TARGET_HOST))
          assert_equal('80', span.get_tag(Ext::NET::TARGET_PORT))
          assert_equal(Ext::HTTP::TYPE, span.span_type)
          assert_equal(Ext::Errors::STATUS, span.status)
          assert_equal('Error 500', span.get_tag(Ext::Errors::TYPE))
          assert_equal('Boom!', span.get_tag(Ext::Errors::MSG))
        end

        def test_client_error
          client.get('/not_found')
          span = request_span

          refute_equal(Ext::Errors::STATUS, span.status)
        end

        def test_custom_error_handling
          custom_handler = ->(env) { (400...600).cover?(env[:status]) }
          client(error_handler: custom_handler).get('not_found')
          span = request_span

          assert_equal(Ext::Errors::STATUS, span.status)
        end

        def test_split_by_domain_option
          client(split_by_domain: true).get('/success')
          span = request_span

          assert_equal(span.name, NAME)
          assert_equal(span.service, 'example.com')
          assert_equal(span.resource, 'GET')
        end

        def test_default_tracing_headers
          response = client.get('/success')
          headers = response.env.request_headers

          refute_includes(headers, Ext::DistributedTracing::HTTP_HEADER_TRACE_ID)
          refute_includes(headers, Ext::DistributedTracing::HTTP_HEADER_PARENT_ID)
        end

        def test_distributed_tracing
          response = client(distributed_tracing: true).get('/success')
          headers = response.env.request_headers
          span = request_span

          assert_equal(headers[Ext::DistributedTracing::HTTP_HEADER_TRACE_ID], span.trace_id.to_s)
          assert_equal(headers[Ext::DistributedTracing::HTTP_HEADER_PARENT_ID], span.span_id.to_s)
        end

        def test_distributed_tracing_disabled
          tracer.enabled = false

          response = client(distributed_tracing: true).get('/success')
          headers = response.env.request_headers
          span = request_span

          # headers should not be set when the tracer is disabled: we do not want the callee
          # to refer to spans which will never be sent to the agent.
          assert_nil(headers[Ext::DistributedTracing::HTTP_HEADER_TRACE_ID])
          assert_nil(headers[Ext::DistributedTracing::HTTP_HEADER_PARENT_ID])
          assert_nil(span, 'disabled tracer, no spans should reach the writer')

          tracer.enabled = true
        end

        def test_global_service_name
          Datadog.configure do |c|
            c.use :faraday, service_name: 'faraday-global'
          end

          client.get('/success')
          span = request_span
          assert_equal('faraday-global', span.service)
        end

        def test_per_request_service_name
          client(service_name: 'adhoc-request').get('/success')
          span = request_span
          assert_equal('adhoc-request', span.service)
        end

        private

        attr_reader :client

        def client(options = {})
          ::Faraday.new('http://example.com') do |builder|
            builder.use(:ddtrace, options)
            builder.adapter(:test) do |stub|
              stub.get('/success') { |_| [200, {}, 'OK'] }
              stub.post('/failure') { |_| [500, {}, 'Boom!'] }
              stub.get('/not_found') { |_| [404, {}, 'Not Found.'] }
            end
          end
        end

        def request_span
          tracer.writer.spans.find { |span| span.name == NAME }
        end

        def tracer
          ::Faraday.datadog_pin.tracer
        end
      end
    end
  end
end
