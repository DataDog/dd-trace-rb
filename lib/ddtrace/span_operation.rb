require 'forwardable'

require 'datadog/core/environment/identity'
require 'ddtrace/ext/runtime'
require 'ddtrace/span'
require 'ddtrace/forced_tracing'

module Datadog
  # Represents the act of taking a span measurement.
  # It gives a Span a context which can be used to
  # manage and decorate the Span.
  # When completed, it yields the Span.
  class SpanOperation
    extend Forwardable

    INCLUDED_METHODS = [:==].to_set.freeze
    EXCLUDED_METHODS = [:finish, :parent, :parent=].to_set.freeze

    def initialize(span_name, options = {})
      # Resolve service name
      parent = options[:child_of]
      options[:service] ||= parent.service unless parent.nil?

      # Build span
      @span = Span.new(
        span_name,
        options
      )
      @tracer = options[:tracer]
      @context = options[:context]

      # Add span to the context, if provided.
      @context.add_span(self) if @context

      if parent.nil?
        # Root span: set default tags.
        set_tag(Datadog::Ext::Runtime::TAG_PID, Process.pid)
        set_tag(Datadog::Ext::Runtime::TAG_ID, Datadog::Core::Environment::Identity.id)
      else
        # Only set parent if explicitly provided.
        # We don't want it to override context-derived
        # IDs if it's a distributed trace w/o a parent span.
        self.parent = parent
      end

      # Set tags if provided.
      set_tags(options[:tags]) if options.key?(:tags)
    end

    attr_reader :parent
    attr_accessor :span, :tracer, :context

    # Set span parent
    def parent=(parent)
      @parent = parent
      span.parent = parent && parent.span
    end

    def finish(end_time = nil)
      return span if finished?

      # Stop the span
      span.stop(end_time)

      begin
        context.close_span(self) if context
        tracer.record_span(self) if tracer
      rescue StandardError => e
        Datadog.logger.debug("error recording finished trace: #{e} Backtrace: #{e.backtrace.first(3)}")
        Datadog.health_metrics.error_span_finish(1, tags: ["error:#{e.class.name}"])
      end

      span
    end

    # Forward instance methods except ones that would cause identity issues
    def_delegators :span, *(Span.instance_methods(false).to_set - EXCLUDED_METHODS)

    # Additional extensions
    prepend ForcedTracing::SpanOperation
  end
end
