require 'ddtrace/ext/correlation'
require 'ddtrace/environment'

module Datadog
  # Contains behavior for managing correlations with tracing
  # e.g. Retrieve a correlation to the current trace for logging, etc.
  module Correlation
    # Struct representing correlation
    Identifier = Struct.new(:trace_id, :span_id, :env, :version) do
      def initialize(*args)
        super
        self.trace_id = trace_id || 0
        self.span_id = span_id || 0
        self.env = env || Datadog::Environment.env
        self.version = version || Datadog::Environment.version
      end

      def to_s
        str =  "#{Ext::Correlation::ATTR_TRACE_ID}=#{trace_id}"
        str += " #{Ext::Correlation::ATTR_SPAN_ID}=#{span_id}"
        str += " #{Ext::Correlation::ATTR_ENV}=#{env}"
        str += " #{Ext::Correlation::ATTR_VERSION}=#{version}"
        str
      end
    end.freeze

    module_function

    # Produces a CorrelationIdentifier from the Context provided
    def identifier_from_context(context)
      return Identifier.new.freeze if context.nil?
      Identifier.new(context.trace_id, context.span_id).freeze
    end
  end
end
