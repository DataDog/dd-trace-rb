module Datadog
  # Contains behavior for managing correlations with tracing
  # e.g. Retrieve a correlation to the current trace for logging, etc.
  module Correlation
    # Struct representing correlation
    Identifier = Struct.new(:trace_id, :span_id)
    NULL_IDENTIFIER = Identifier.new.freeze

    module_function

    # Produces a CorrelationIdentifier from the Context provided
    def identifier_from_context(context)
      return NULL_IDENTIFIER if context.nil?
      Identifier.new(context.trace_id, context.span_id).freeze
    end
  end
end
