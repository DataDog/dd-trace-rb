require 'helper'
require 'dalli'
require 'ddtrace'
require 'ddtrace/contrib/dalli/patcher'

module Datadog
  module Contrib
    module Dalli
      class InstrumentationTest < Minitest::Test
        TEST_HOST = ENV.fetch('TEST_MEMCACHED_PORT', '127.0.0.1')
        TEST_PORT = ENV.fetch('TEST_MEMCACHED_PORT', '41121')

        def setup
          @client = ::Dalli::Client.new("#{TEST_HOST}:#{TEST_PORT}")
          @tracer = enable_test_tracer!
        end

        def test_call_instrumentation
          client.set('abc', 123)
          try_wait_until { all_spans.any? }

          span = all_spans.first
          assert_equal(1, all_spans.size)
          assert_equal('memcached', span.service)
          assert_equal('memcached.command', span.name)
          assert_equal('SET', span.resource)
          assert_equal('set abc 123 0 0', span.get_tag('memcached.command'))
          assert_equal(TEST_HOST, span.get_tag('out.host'))
          assert_equal(TEST_PORT, span.get_tag('out.port'))
        end

        private

        attr_reader :tracer, :client

        def all_spans
          tracer.writer.spans(:keep)
        end

        def enable_test_tracer!
          Monkey.patch_module(:dalli)
          get_test_tracer.tap { |tracer| pin.tracer = tracer }
        end

        def pin
          ::Dalli.datadog_pin
        end
      end
    end
  end
end
