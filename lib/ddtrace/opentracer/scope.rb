# typed: true
module Datadog
  module OpenTracer
    # OpenTracing adapter for scope
    # @public_api
    class Scope < ::OpenTracing::Scope
      # @public_api
      attr_reader \
        :manager,
        :span

      # @public_api
      def initialize(manager:, span:)
        @manager = manager
        @span = span
      end
    end
  end
end
