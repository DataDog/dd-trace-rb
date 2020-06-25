require 'ddtrace/ext/correlation'
require 'ddtrace/environment'

module Datadog
  # Contains behavior for managing correlations with tracing
  # e.g. Retrieve a correlation to the current trace for logging, etc.
  module Correlation
    # Struct representing correlation
    Identifier = Struct.new(:trace_id, :span_id, :env, :service, :version) do
      def initialize(*args)
        super
        self.trace_id = trace_id || 0
        self.span_id = span_id || 0
        self.env = env || Datadog.configuration.env
        self.service = service || Datadog.configuration.service
        self.version = version || Datadog.configuration.version
      end

      def to_s
        attributes = []
        attributes << "#{Ext::Correlation::ATTR_ENV}=#{env}" unless env.nil?
        attributes << "#{Ext::Correlation::ATTR_SERVICE}=#{service}" unless service.nil?
        attributes << "#{Ext::Correlation::ATTR_VERSION}=#{version}" unless version.nil?
        attributes << "#{Ext::Correlation::ATTR_TRACE_ID}=#{trace_id}"
        attributes << "#{Ext::Correlation::ATTR_SPAN_ID}=#{span_id}"
        attributes.join(' ')
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
