require 'minitest'
require 'ddtrace'
require 'helper'
require 'ddtrace/sync_writer'

module Datadog
  class SyncWriterTest < Minitest::Test
    def setup
      @transport = SpyTransport.new
      @sync_writer = SyncWriter.new(transport: @transport)
    end

    def test_sync_write
      trace = get_test_traces(1).first
      services = get_test_services

      @sync_writer.write(trace, services)
      assert_includes(@transport.calls, [:traces, [trace]])
      assert_includes(@transport.calls, [:services, services])
    end

    def test_sync_write_filtering
      trace1 = [Span.new(nil, 'span_1')]
      trace2 = [Span.new(nil, 'span_2')]

      Pipeline.before_flush(
        Pipeline::SpanFilter.new { |span| span.name == 'span_1' }
      )

      @sync_writer.write(trace1, {})
      @sync_writer.write(trace2, {})

      refute_includes(@transport.calls, [:traces, [trace1]])
      assert_includes(@transport.calls, [:traces, [trace2]])
    end

    def test_itegration_with_tracer
      tracer = Tracer.new(writer: @sync_writer)
      span = tracer.start_span('foo.bar')
      span.finish

      assert_includes(@transport.calls, [:traces, [[span]]])
    end

    def teardown
      Pipeline.processors = []
    end

    class SpyTransport
      def initialize
        @mutex = Mutex.new
      end

      def send(*call_arguments)
        @mutex.synchronize { calls << call_arguments }
      end

      def calls
        @calls ||= []
      end
    end
  end
end
