module Datadog
  module OpenTracer
    # OpenTracing adapter for scope
    class Scope < ::OpenTracing::Scope
      attr_reader \
        :manager,
        :span

      def initialize(manager:, span:)
        @manager = manager
        @span = span
      end
    end
  end
end
