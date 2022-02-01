# typed: false
require 'logger'
require 'pathname'

require 'datadog/core/environment/identity'
require 'datadog/core/environment/ext'

require 'ddtrace/context_provider'
require 'ddtrace/context'
require 'ddtrace/correlation'
require 'ddtrace/event'
require 'datadog/core/logger'
require 'ddtrace/sampler'
require 'ddtrace/sampling'
require 'ddtrace/span_operation'
require 'ddtrace/trace_flush'
require 'ddtrace/trace_operation'
require 'ddtrace/writer'

module Datadog
  # A {Datadog::Tracer} keeps track of the time spent by an application processing a single operation. For
  # example, a trace can be used to track the entire time spent processing a complicated web request.
  # Even though the request may require multiple resources and machines to handle the request, all
  # of these function calls and sub-requests would be encapsulated within a single trace.
  # rubocop:disable Metrics/ClassLength
  class Tracer
    attr_reader \
      :trace_flush,
      :provider,
      :sampler,
      :tags

    attr_accessor \
      :default_service,
      :enabled,
      :writer

    # Initialize a new {Datadog::Tracer} used to create, sample and submit spans that measure the
    # time of sections of code.
    #
    # @param trace_flush [Datadog::TraceFlush] responsible for flushing spans from the execution context
    # @param context_provider [Datadog::DefaultContextProvider] ensures different execution contexts have distinct traces
    # @param default_service [String] A fallback value for {Datadog::Span#service}, as spans without service are rejected
    # @param enabled [Boolean] set if the tracer submits or not spans to the local agent
    # @param sampler [Datadog::Sampler] a tracer sampler, responsible for filtering out spans when needed
    # @param tags [Hash] default tags added to all spans
    # @param writer [Datadog::Writer] consumes traces returned by the provided +trace_flush+
    def initialize(
      trace_flush: Datadog::TraceFlush::Finished.new,
      context_provider: Datadog::DefaultContextProvider.new,
      default_service: Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME,
      enabled: true,
      sampler: PrioritySampler.new(base_sampler: Datadog::AllSampler.new, post_sampler: Sampling::RuleSampler.new),
      tags: {},
      writer: Datadog::Writer.new
    )
      @trace_flush = trace_flush
      @default_service = default_service
      @enabled = enabled
      @provider = context_provider
      @sampler = sampler
      @tags = tags
      @writer = writer
    end

    # Return a {Datadog::SpanOperation span_op} and {Datadog::TraceOperation trace_op} that will trace an operation
    # called `name`. You could trace your code
    # using a <tt>do-block</tt> like:
    #
    # ```
    # tracer.trace('web.request') do |span_op, trace_op|
    #   span_op.service = 'my-web-site'
    #   span_op.resource = '/'
    #   span_op.set_tag('http.method', request.request_method)
    #   do_something()
    # end
    # ```
    #
    # The {#trace} method can also be used without a block in this way:
    # ```
    # span_op = tracer.trace('web.request', service: 'my-web-site')
    # do_something()
    # span_op.finish()
    # ```
    #
    # Remember that in this case, calling {Datadog::SpanOperation#finish} is mandatory.
    #
    # When a Trace is started, {#trace} will store the created span; subsequent spans will
    # become its children and will inherit some properties:
    # ```
    # parent = tracer.trace('parent')   # has no parent span
    # child  = tracer.trace('child')    # is a child of 'parent'
    # child.finish()
    # parent.finish()
    # parent2 = tracer.trace('parent2') # has no parent span
    # parent2.finish()
    # ```
    #
    # @param [String] name {Datadog::Span} operation name.
    #   See {https://docs.datadoghq.com/tracing/guide/configuring-primary-operation/ Primary Operations in Services}.
    # @param [Datadog::TraceDigest] continue_from continue a trace from a {Datadog::TraceDigest}.
    #   Used for linking traces that are executed asynchronously.
    # @param [Boolean] autostart whether to autostart the span, if no block is provided.
    # @param [Proc] on_error a block that overrides error handling behavior for this operation.
    # @param [String] resource the resource this span refers, or `name` if it's missing
    # @param [String] service the service name for this span.
    # @param [Time] start_time time which the span should have started.
    # @param [Hash<String,String>] tags extra tags which should be added to the span.
    # @param [String] type the type of the span. See {Datadog::Ext::AppTypes}.
    # @return [Object] If a block is provided, returns the result of the block execution.
    # @return [Datadog::SpanOperation] If no block is provided, returns the active, unfinished {Datadog::SpanOperation}.
    # @yield Optional block where new newly created {Datadog::SpanOperation} captures the execution.
    # @yieldparam [Datadog::SpanOperation] span_op the newly created and active [Datadog::SpanOperation]
    # @yieldparam [Datadog::TraceOperation] trace_op the active [Datadog::TraceOperation]
    # rubocop:disable Lint/UnderscorePrefixedVariableName
    def trace(
      name,
      continue_from: nil,
      _context: nil,
      **span_options,
      &block
    )
      return skip_trace(name, &block) unless enabled

      context, trace = nil

      # Resolve the trace
      begin
        context = _context || call_context
        active_trace = context.active_trace
        trace = if continue_from || active_trace.nil?
                  start_trace(continue_from: continue_from)
                else
                  active_trace
                end
      rescue StandardError => e
        Datadog.logger.debug { "Failed to trace: #{e}" }

        # Tracing failed: fallback and run code without tracing.
        return skip_trace(name, &block)
      end

      # Activate and start the trace
      if block
        context.activate!(trace) do
          start_span(name, _trace: trace, **span_options, &block)
        end
      else
        # Setup trace activation/deactivation
        manual_trace_activation!(context, trace)

        # Return the new span
        start_span(name, _trace: trace, **span_options)
      end
    end
    # rubocop:enable Lint/UnderscorePrefixedVariableName

    # Set the given key / value tag pair at the tracer level. These tags will be
    # appended to each span created by the tracer. Keys and values must be strings.
    # @example
    #   tracer.set_tags('env' => 'prod', 'component' => 'core')
    def set_tags(tags)
      string_tags = tags.collect { |k, v| [k.to_s, v] }.to_h
      @tags = @tags.merge(string_tags)
    end

    # The active, unfinished trace, representing the current instrumentation context.
    #
    # The active trace is thread-local.
    #
    # @param [Thread] key Thread to retrieve trace from. Defaults to current thread. For internal use only.
    # @return [Datadog::TraceSegment] the active trace
    # @return [nil] if no trace is active
    def active_trace(key = nil)
      call_context(key).active_trace
    end

    # The active, unfinished span, representing the currently instrumented application section.
    #
    # The active span belongs to an {.active_trace}.
    #
    # @param [Thread] key Thread to retrieve trace from. Defaults to current thread. For internal use only.
    # @return [Datadog::SpanOperation] the active span
    # @return [nil] if no trace is active, and thus no span is active
    def active_span(key = nil)
      trace = active_trace(key)
      trace.active_span if trace
    end

    # Information about the currently active trace.
    #
    # The most common use cases are tagging log messages and metrics.
    #
    # @param [Thread] key Thread to retrieve trace from. Defaults to current thread. For internal use only.
    # @return [Datadog::Correlation::Identifier] correlation object
    def active_correlation(key = nil)
      trace = active_trace(key)
      Datadog::Correlation.identifier_from_digest(
        trace && trace.to_digest
      )
    end

    # Setup a new trace to continue from where another
    # trace left off.
    #
    # Used to continue distributed or async traces.
    #
    # @param [Datadog::TraceDigest] digest continue from the {Datadog::TraceDigest}.
    # @param [Thread] key Thread to retrieve trace from. Defaults to current thread. For internal use only.
    # @return [Object] If a block is provided, the result of the block execution.
    # @return [Datadog::TraceOperation] If no block, the active {Datadog::TraceOperation}.
    # @yield Optional block where this {#continue_trace!} `digest` scope is active.
    #   If no block, the `digest` remains active after {#continue_trace!} returns.
    def continue_trace!(digest, key = nil, &block)
      # Only accept {TraceDigest} as a digest.
      # Otherwise, create a new execution context.
      digest = nil unless digest.is_a?(TraceDigest)

      # Start a new trace from the digest
      context = call_context(key)
      original_trace = active_trace(key)
      trace = start_trace(continue_from: digest)

      # If block hasn't been given; we need to manually deactivate
      # this trace. Subscribe to the trace finished event to do this.
      subscribe_trace_deactivation!(context, trace, original_trace) unless block

      context.activate!(trace, &block)
    end

    # @!visibility private
    # TODO: make this private
    def trace_completed
      @trace_completed ||= TraceCompleted.new
    end

    # Triggered whenever a trace is completed
    class TraceCompleted < Datadog::Event
      def initialize
        super(:trace_completed)
      end

      # NOTE: Ignore Rubocop rule. This definition allows for
      #       description of and constraints on arguments.
      # rubocop:disable Lint/UselessMethodDefinition
      def publish(trace)
        super(trace)
      end
      # rubocop:enable Lint/UselessMethodDefinition
    end

    # Shorthand that calls the `shutdown!` method of a registered worker.
    # It's useful to ensure that the Trace Buffer is properly flushed before
    # shutting down the application.
    #
    # @example
    #   tracer.trace('operation_name', service='rake_tasks') do |span_op|
    #     span_op.set_tag('task.name', 'script')
    #   end
    #
    #   tracer.shutdown!
    def shutdown!
      return unless @enabled

      @writer.stop if @writer
    end

    private

    # Return the current active {Context} for this traced execution. This method is
    # automatically called when calling Tracer.trace or Tracer.start_span,
    # but it can be used in the application code during manual instrumentation.
    #
    # This method makes use of a {ContextProvider} that is automatically set during the tracer
    # initialization, or while using a library instrumentation.
    #
    # @param [Thread] key Thread to retrieve tracer from. Defaults to current thread.
    def call_context(key = nil)
      @provider.context(key)
    end

    def build_trace(digest = nil)
      # Resolve hostname if configured
      hostname = Core::Environment::Socket.hostname if Datadog::Tracing.configuration.report_hostname
      hostname = hostname && !hostname.empty? ? hostname : nil

      if digest
        TraceOperation.new(
          hostname: hostname,
          id: digest.trace_id,
          origin: digest.trace_origin,
          parent_span_id: digest.span_id,
          sampling_priority: digest.trace_sampling_priority
        )
      else
        TraceOperation.new(
          hostname: hostname
        )
      end
    end

    def bind_trace_events!(trace_op)
      events = trace_op.send(:events)

      unless events.span_before_start.subscriptions[:tracer_span_before_start]
        events.span_before_start.subscribe(:tracer_span_before_start) do |event_span_op, event_trace_op|
          event_trace_op.service ||= @default_service
          event_span_op.service ||= @default_service
          sample_trace(event_trace_op) if event_span_op && event_span_op.parent_id == 0
        end
      end

      unless events.span_finished.subscriptions[:tracer_span_finished]
        events.span_finished.subscribe(:tracer_span_finished) do |_event_span, event_trace_op|
          flush_trace(event_trace_op)
        end
      end
    end

    def start_trace(continue_from: nil)
      # Build a new trace using digest if provided.
      trace = build_trace(continue_from)

      # Bind trace events: sample trace, set default service, flush spans.
      bind_trace_events!(trace)

      trace
    end

    def start_span(
      name,
      continue_from: nil,
      on_error: nil,
      resource: nil,
      service: nil,
      start_time: nil,
      tags: nil,
      type: nil,
      **kwargs,
      &block
    )
      trace = kwargs[:_trace] || start_trace(continue_from: continue_from)
      autostart = kwargs.key?(:_autostart) ? kwargs[:_autostart] : true

      # Bind trace events: sample trace, set default service, flush spans.
      # NOTE: This might be redundant sometimes (given #start_trace does this)
      #       however, it is necessary because the Context/TraceOperation may
      #       have been provided by a source outside the tracer e.g. OpenTracing
      bind_trace_events!(trace)

      span_options = {
        events: build_span_events,
        on_error: on_error,
        resource: resource,
        service: service,
        start_time: start_time,
        tags: resolve_tags(tags),
        type: type || kwargs[:span_type]
      }

      if block
        # Ignore start time if a block has been given
        span_options.delete(:start_time)
        trace.measure(name, **span_options, &block)
      else
        # Return the new span
        span = trace.build_span(name, **span_options)
        span.start(start_time) if autostart
        span
      end
    end

    def build_span_events(events = nil)
      case events
      when SpanOperation::Events
        events
      when Hash
        SpanOperation::Events.build(events)
      else
        SpanOperation::Events.new
      end
    end

    def resolve_tags(tags)
      if @tags.any? && tags
        # Combine default tags with provided tags,
        # preferring provided tags.
        @tags.merge(tags)
      else
        # Use provided tags or default tags if none.
        tags || @tags.dup
      end
    end

    # Manually activate and deactivate the trace, when the span completes.
    def manual_trace_activation!(context, trace)
      # Get the original trace to restore
      original_trace = context.active_trace

      # Setup the deactivation callback
      subscribe_trace_deactivation!(context, trace, original_trace)

      # Activate the trace
      # Skip this, if it would have no effect.
      context.activate!(trace) unless trace == original_trace
    end

    # Reactivate the original trace when trace completes
    def subscribe_trace_deactivation!(context, trace, original_trace)
      # Don't override this event if it's set.
      # The original event should reactivate the original trace correctly.
      return if trace.send(:events).trace_finished.subscriptions[:tracer_deactivate_trace]

      trace.send(:events).trace_finished.subscribe(:tracer_deactivate_trace) do |*_|
        context.activate!(original_trace)
      end
    end

    # Sample a span, tagging the trace as appropriate.
    def sample_trace(trace_op)
      begin
        @sampler.sample!(trace_op)
      rescue StandardError => e
        Datadog.logger.debug { "Failed to sample trace: #{e}" }
      end
    end

    # Flush finished spans from the trace buffer, send them to writer.
    def flush_trace(trace_op)
      begin
        trace = @trace_flush.consume!(trace_op)
        write(trace) if trace && !trace.empty?
      rescue StandardError => e
        Datadog.logger.debug { "Failed to flush trace: #{e}" }
      end
    end

    # Send the trace to the writer to enqueue the spans list in the agent
    # sending queue.
    def write(trace)
      return unless trace && @writer

      if Datadog.configuration.diagnostics.debug
        Datadog.logger.debug { "Writing #{trace.length} spans (enabled: #{@enabled})\n#{trace.spans.pretty_inspect}" }
      end

      @writer.write(trace)
      trace_completed.publish(trace)
    end

    # TODO: Make these dummy objects singletons to preserve memory.
    def skip_trace(name)
      span = SpanOperation.new(name)

      if block_given?
        trace = TraceOperation.new
        yield(span, trace)
      else
        span
      end
    end
  end
end
