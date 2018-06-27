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

      # @return [ScopeManager] the current ScopeManager.
      def scope_manager
        @scope_manager ||= ThreadLocalScopeManager.new
      end

      # Returns a newly started and activated Scope.
      #
      # If the Tracer's ScopeManager#active is not nil, no explicit references
      # are provided, and `ignore_active_scope` is false, then an inferred
      # References#CHILD_OF reference is created to the ScopeManager#active's
      # SpanContext when start_active is invoked.
      #
      # @param operation_name [String] The operation name for the Span
      # @param child_of [SpanContext, Span] SpanContext that acts as a parent to
      #        the newly-started Span. If a Span instance is provided, its
      #        context is automatically substituted. See [Reference] for more
      #        information.
      #
      #   If specified, the `references` parameter must be omitted.
      # @param references [Array<Reference>] An array of reference
      #   objects that identify one or more parent SpanContexts.
      # @param start_time [Time] When the Span started, if not now
      # @param tags [Hash] Tags to assign to the Span at start time
      # @param ignore_active_scope [Boolean] whether to create an implicit
      #   References#CHILD_OF reference to the ScopeManager#active.
      # @param finish_on_close [Boolean] whether span should automatically be
      #   finished when Scope#close is called
      # @yield [Scope] If an optional block is passed to start_active it will
      #   yield the newly-started Scope. If `finish_on_close` is true then the
      #   Span will be finished automatically after the block is executed.
      # @return [Scope] The newly-started and activated Scope
      def start_active_span(operation_name,
                            child_of: nil,
                            references: nil,
                            start_time: Time.now,
                            tags: nil,
                            ignore_active_scope: false,
                            finish_on_close: true)
        span = start_span(
          operation_name,
          child_of: child_of,
          references: references,
          start_time: start_time,
          tags: tags,
          ignore_active_scope: ignore_active_scope
        )

        scope_manager.activate(span, finish_on_close: finish_on_close).tap do |scope|
          if block_given?
            begin
              yield(scope)
            ensure
              scope.close
            end
          end
        end
      end

      # Like #start_active_span, but the returned Span has not been registered via the
      # ScopeManager.
      #
      # @param operation_name [String] The operation name for the Span
      # @param child_of [SpanContext, Span] SpanContext that acts as a parent to
      #        the newly-started Span. If a Span instance is provided, its
      #        context is automatically substituted. See [Reference] for more
      #        information.
      #
      #   If specified, the `references` parameter must be omitted.
      # @param references [Array<Reference>] An array of reference
      #   objects that identify one or more parent SpanContexts.
      # @param start_time [Time] When the Span started, if not now
      # @param tags [Hash] Tags to assign to the Span at start time
      # @param ignore_active_scope [Boolean] whether to create an implicit
      #   References#CHILD_OF reference to the ScopeManager#active.
      # @return [Span] the newly-started Span instance, which has not been
      #   automatically registered via the ScopeManager
      def start_span(operation_name,
                     child_of: nil,
                     references: nil,
                     start_time: Time.now,
                     tags: nil,
                     ignore_active_scope: false)
        # Get the parent Datadog span
        parent_datadog_span = case child_of
                              when Span
                                child_of.datadog_span
                              else
                                ignore_active_scope ? nil : scope_manager.active && scope_manager.active.span.datadog_span
                              end

        # Build the new Datadog span
        datadog_span = datadog_tracer.start_span(
          operation_name,
          child_of: parent_datadog_span,
          start_time: start_time,
          tags: tags || {}
        )

        # Derive the OpenTracer::SpanContext to inherit from
        parent_span_context = case child_of
                              when Span
                                child_of.context
                              when SpanContext
                                child_of
                              else
                                ignore_active_scope ? nil : scope_manager.active && scope_manager.active.span.context
                              end

        # Build or extend the OpenTracer::SpanContext
        span_context = if parent_span_context
                         SpanContextFactory.clone(span_context: parent_span_context)
                       else
                         SpanContextFactory.build(datadog_context: datadog_span.context)
                       end

        # Wrap the Datadog span and OpenTracer::Span context in a OpenTracer::Span
        Span.new(datadog_span: datadog_span, span_context: span_context)
      end

      # Inject a SpanContext into the given carrier
      #
      # @param span_context [SpanContext]
      # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK]
      # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
      def inject(span_context, format, carrier)
        case format
        when OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK
          return nil
        else
          warn 'Unknown inject format'
        end
      end

      # Extract a SpanContext in the given format from the given carrier.
      #
      # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK]
      # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
      # @return [SpanContext, nil] the extracted SpanContext or nil if none could be found
      def extract(format, carrier)
        case format
        when OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK
          return SpanContext::NOOP_INSTANCE
        else
          warn 'Unknown extract format'
          nil
        end
      end
    end
  end
end
