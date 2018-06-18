require 'ddtrace/tracer'

module Datadog
  module OpenTracer
    # OpenTracing adapter for Datadog::Tracer
    class Tracer < ::OpenTracing::Tracer
      extend Forwardable

      attr_reader \
        :datadog_tracer

      def_delegators \
        :datadog_tracer,
        :configure

      def initialize(options = {})
        super()
        @datadog_tracer = Datadog::Tracer.new(options)
      end
    end
  end
end
