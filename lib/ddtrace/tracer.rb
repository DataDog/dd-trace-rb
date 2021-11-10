# typed: false
require 'logger'
require 'pathname'

require 'datadog/core/environment/identity'
require 'ddtrace/ext/environment'

require 'ddtrace/context'
require 'ddtrace/correlation'
require 'ddtrace/event'
require 'ddtrace/logger'
require 'ddtrace/sampler'
require 'ddtrace/sampling'
require 'ddtrace/span_operation'
require 'ddtrace/utils/only_once'
require 'ddtrace/writer'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Tracer keeps track of the time spent by an application processing a single operation. For
  # example, a trace can be used to track the entire time spent processing a complicated web request.
  # Even though the request may require multiple resources and machines to handle the request, all
  # of these function calls and sub-requests would be encapsulated within a single trace.
  # rubocop:disable Metrics/ClassLength
  class Tracer
    ALLOWED_SPAN_OPTIONS = [
      :child_of,
      :on_error,
      :parent_id,
      :resource,
      :service,
      :span_type,
      :start_time,
      :tags,
      :trace_id,
      :type
    ].freeze

    attr_reader :sampler, :tags, :provider, :context_flush
    attr_accessor :enabled, :writer
    attr_writer :default_service

    # Shorthand that calls the `shutdown!` method of a registered worker.
    # It's useful to ensure that the Trace Buffer is properly flushed before
    # shutting down the application.
    #
    # For instance:
    #
    #   tracer.trace('operation_name', service='rake_tasks') do |span_op|
    #     span_op.set_tag('task.name', 'script')
    #   end
    #
    #   tracer.shutdown!
    #
    def shutdown!
      return unless @enabled

      @writer.stop unless @writer.nil?
    end

    # Return the current active \Context for this traced execution. This method is
    # automatically called when calling Tracer.trace or Tracer.start_span,
    # but it can be used in the application code during manual instrumentation.
    #
    # This method makes use of a \ContextProvider that is automatically set during the tracer
    # initialization, or while using a library instrumentation.
    def call_context(key = nil)
      @provider.context(key)
    end

    # Initialize a new \Tracer used to create, sample and submit spans that measure the
    # time of sections of code. Available +options+ are:
    #
    # * +enabled+: set if the tracer submits or not spans to the local agent. It's enabled
    #   by default.
    def initialize(options = {})
      # Configurable options
      @context_flush = if options[:context_flush]
                         options[:context_flush]
                       elsif options[:partial_flush]
                         Datadog::ContextFlush::Partial.new(options)
                       else
                         Datadog::ContextFlush::Finished.new
                       end

      @default_service = options[:default_service]
      @enabled = options.fetch(:enabled, true)
      @provider = options[:context_provider] || Datadog::DefaultContextProvider.new
      @sampler = options.fetch(:sampler, Datadog::AllSampler.new)
      @tags = options.fetch(:tags, {})
      @writer = options.fetch(:writer) { Datadog::Writer.new }

      # Instance variables
      @mutex = Mutex.new

      # Enable priority sampling by default
      activate_priority_sampling!(@sampler)
    end

    # Updates the current \Tracer instance, so that the tracer can be configured after the
    # initialization. Available +options+ are:
    #
    # * +enabled+: set if the tracer submits or not spans to the trace agent
    # * +hostname+: change the location of the trace agent
    # * +port+: change the port of the trace agent
    # * +partial_flush+: enable partial trace flushing
    #
    # For instance, if the trace agent runs in a different location, just:
    #
    #   tracer.configure(hostname: 'agent.service.consul', port: '8777')
    #
    def configure(options = {})
      enabled = options.fetch(:enabled, nil)

      # Those are rare "power-user" options.
      sampler = options.fetch(:sampler, nil)

      @enabled = enabled unless enabled.nil?
      @sampler = sampler unless sampler.nil?

      configure_writer(options)

      if options.key?(:context_flush) || options.key?(:partial_flush)
        @context_flush = if options[:context_flush]
                           options[:context_flush]
                         elsif options[:partial_flush]
                           Datadog::ContextFlush::Partial.new(options)
                         else
                           Datadog::ContextFlush::Finished.new
                         end
      end
    end

    # A default value for service. One should really override this one
    # for non-root spans which have a parent. However, root spans without
    # a service would be invalid and rejected.
    def default_service
      @default_service ||= Datadog::Ext::Environment::FALLBACK_SERVICE_NAME
    end

    # Set the given key / value tag pair at the tracer level. These tags will be
    # appended to each span created by the tracer. Keys and values must be strings.
    # A valid example is:
    #
    #   tracer.set_tags('env' => 'prod', 'component' => 'core')
    def set_tags(tags)
      string_tags = tags.collect { |k, v| [k.to_s, v] }.to_h
      @tags = @tags.merge(string_tags)
    end

    # Build a span that will trace an operation called \name. This method allows
    # parenting passing \child_of as an option. If it's missing, the newly created span is a
    # root span. Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or \name if it's missing
    # * +type+: the type of the span (such as \http, \db and so on)
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    # * +tags+: extra tags which should be added to the span.
    def build_span(name, options = {})
      # Resolve span options:
      # Context, parent, service name, etc.
      options = build_span_options(options)
      context = options[:context]
      on_error = options.delete(:on_error)

      # Build a new span operation
      span_op = Datadog::SpanOperation.new(name, **options)

      # Add span operation to context
      if context && context.add_span(span_op)
        # Subscribe to finish event to close and record.
        subscribe_span_finish(span_op, context)
      else
        # Could not add the span (context is probably full)
        # Disassociate the span from the context
        span_op.send(:context=, nil)
      end

      # Subscribe to the error event to run any custom error behavior.
      subscribe_on_error(span_op, on_error)

      # If it's a root span, sample it.
      @sampler.sample!(span_op) unless options[:child_of]

      span_op
    end

    # Build and start a span that will trace an operation called \name. This method allows
    # parenting passing \child_of as an option. If it's missing, the newly created span is a
    # root span. Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or \name if it's missing
    # * +type+: the type of the span (such as \http, \db and so on)
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    # * +start_time+: when the span actually starts (defaults to \now)
    # * +tags+: extra tags which should be added to the span.
    def start_span(name, options = {})
      span_op = build_span(name, options)
      span_op.start(options[:start_time])
      span_op
    end

    # Return a +span+ that will trace an operation called +name+. You could trace your code
    # using a <tt>do-block</tt> like:
    #
    #   tracer.trace('web.request') do |span_op|
    #     span_op.service = 'my-web-site'
    #     span_op.resource = '/'
    #     span_op.set_tag('http.method', request.request_method)
    #     do_something()
    #   end
    #
    # The <tt>tracer.trace()</tt> method can also be used without a block in this way:
    #
    #   span_op = tracer.trace('web.request', service: 'my-web-site')
    #   do_something()
    #   span_op.finish()
    #
    # Remember that in this case, calling <tt>span_op.finish()</tt> is mandatory.
    #
    # When a Trace is started, <tt>trace()</tt> will store the created span; subsequent spans will
    # become it's children and will inherit some properties:
    #
    #   parent = tracer.trace('parent')     # has no parent span
    #   child  = tracer.trace('child')      # is a child of 'parent'
    #   child.finish()
    #   parent.finish()
    #   parent2 = tracer.trace('parent2')   # has no parent span
    #   parent2.finish()
    #
    # Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or \name if it's missing
    # * +type+: the type of the span (such as \http, \db and so on)
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    #   If not set, defaults to Tracer.call_context. If +nil+, a fresh \Context is created.
    # * +tags+: extra tags which should be added to the span.
    def trace(name, options = {}, &block)
      if block
        # If building a span somehow fails, try to run the original code anyways.
        # This may help if it were manual instrumentation. However, if the code
        # block in question attempts to access the non-existent span, then it will
        # throw an error and fail anyways.
        #
        # TODO: Should migrate any span mutation instructions into its own block,
        #       separate from the actual instrumented code.
        begin
          # Filter out invalid options & build a span
          options = options.dup.tap { |opts| opts.delete(:start_time) }
          span_op = build_span(name, options)
        rescue StandardError => e
          Datadog.logger.debug("Failed to build span: #{e}")
          yield(nil)
        else
          span_op.measure(&block)
        end
      else
        start_span(name, options)
      end
    end

    # Record the given +context+. For compatibility with previous versions,
    # +context+ can also be a span. It is similar to the +child_of+ argument,
    # method will figure out what to do, submitting a +span+ for recording
    # is like trying to record its +context+.
    def record(context)
      context = context.context if context.is_a?(Datadog::SpanOperation)
      return if context.nil?

      record_context(context)
    end

    # Return the current active span or +nil+.
    def active_span(key = nil)
      call_context(key).current_span
    end

    # Return the current active root span or +nil+.
    def active_root_span(key = nil)
      call_context(key).current_root_span
    end

    # Return a CorrelationIdentifier for active span
    def active_correlation(key = nil)
      Datadog::Correlation.identifier_from_context(call_context(key))
    end

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

    private

    def build_span_options(options = {})
      # Filter out disallowed options
      options = ALLOWED_SPAN_OPTIONS.each_with_object({}) do |option, opts|
        opts[option] = options[option] if options.key?(option)
        opts
      end

      # Resolve context and parent, unless parenting is explicitly nullified.
      if options.key?(:child_of) && options[:child_of].nil?
        context = Context.new
        parent = nil
      else
        context, parent = resolve_context_and_parent(options[:child_of])
      end

      # Build span options
      options[:child_of] = parent
      options[:context] = context
      options[:service] ||= (parent && parent.service) || default_service
      options[:tags] = resolve_tags(options[:tags])

      # If a parent span isn't defined, use context's trace/span ID if available.
      # Necessary when root span isn't available, e.g. distributed trace.
      unless parent
        if (span_id = (context && context.span_id))
          options[:parent_id] = span_id
        end

        if (trace_id = (context && context.trace_id))
          options[:trace_id] = trace_id
        end
      end

      options
    end

    def resolve_context_and_parent(child_of)
      context = child_of.is_a?(Context) ? child_of : call_context
      parent = if child_of.is_a?(Context)
                 child_of.current_span
               else
                 child_of || context.current_span
               end

      [context, parent]
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

    # Close the span on the context and record the finished span.
    def subscribe_span_finish(span_op, context)
      after_finish = span_op.send(:events).after_finish
      after_finish.subscribe(:tracer_span_finished) do |_span, op|
        begin
          context.close_span(op) if context
          record_span(op)
        rescue StandardError => e
          Datadog.logger.debug("Error closing finished span operation: #{e} Backtrace: #{e.backtrace.first(3)}")
          Datadog.health_metrics.error_span_finish(1, tags: ["error:#{e.class.name}"])
        end
      end
    end

    # Call custom error handler but fallback to default behavior on failure.
    def subscribe_on_error(span_op, error_handler)
      return unless error_handler.respond_to?(:call)

      on_error = span_op.send(:events).on_error
      on_error.wrap(:default) do |original, op, error|
        begin
          error_handler.call(op, error)
        rescue StandardError => e
          Datadog.logger.debug(
            "Custom on_error handler failed, using fallback behavior. \
             Error: #{e.message} Location: #{e.backtrace.first}"
          )
          original.call(op, error) if original
        end
      end
    end

    # Records the span (& its context)
    def record_span(span_op)
      begin
        record_context(span_op.context) if span_op.context
      rescue StandardError => e
        Datadog.logger.debug("Error recording finished trace: #{e} Backtrace: #{e.backtrace.first}")
        Datadog.health_metrics.error_span_finish(1, tags: ["error:#{e.class.name}"])
      end
    end

    # Consume trace from +context+, according to +@context_flush+
    # criteria.
    #
    # \ContextFlush#consume! can return nil or an empty list if the
    # trace is not available to flush or if the trace has not been
    # chosen to be sampled.
    def record_context(context)
      trace = @context_flush.consume!(context)

      write(trace) if @enabled && trace && !trace.empty?
    end

    # Send the trace to the writer to enqueue the spans list in the agent
    # sending queue.
    def write(trace)
      return if @writer.nil?

      if Datadog.configuration.diagnostics.debug
        Datadog.logger.debug("Writing #{trace.length} spans (enabled: #{@enabled})")
        str = String.new('')
        PP.pp(trace, str)
        Datadog.logger.debug(str)
      end

      @writer.write(trace)
      trace_completed.publish(trace)
    end

    # TODO: Move this kind of configuration building out of the tracer.
    #       Tracer should not have this kind of knowledge of writer.
    def configure_writer(options = {})
      sampler = options.fetch(:sampler, nil)
      priority_sampling = options.fetch(:priority_sampling, nil)
      writer = options.fetch(:writer, nil)
      agent_settings = options.fetch(:agent_settings, nil)

      # Compile writer options
      writer_options = options.fetch(:writer_options, {}).dup

      # Re-build the sampler and writer if priority sampling is enabled,
      # but neither are configured. Verify the sampler isn't already a
      # priority sampler too, so we don't wrap one with another.
      if options.key?(:writer)
        if writer.priority_sampler.nil?
          deactivate_priority_sampling!(sampler)
        else
          activate_priority_sampling!(writer.priority_sampler)
        end
      elsif priority_sampling != false && !@sampler.is_a?(PrioritySampler)
        writer_options[:priority_sampler] = activate_priority_sampling!(@sampler)
      elsif priority_sampling == false
        deactivate_priority_sampling!(sampler)
      elsif @sampler.is_a?(PrioritySampler)
        # Make sure to add sampler to options if transport is rebuilt.
        writer_options[:priority_sampler] = @sampler
      end

      writer_options[:agent_settings] = agent_settings if agent_settings

      # Make sure old writer is shut down before throwing away.
      # Don't want additional threads running...
      @writer.stop unless writer.nil?

      @writer = writer || Writer.new(writer_options)
    end

    def activate_priority_sampling!(base_sampler = nil)
      @sampler = if base_sampler.is_a?(PrioritySampler)
                   base_sampler
                 else
                   PrioritySampler.new(
                     base_sampler: base_sampler,
                     post_sampler: Sampling::RuleSampler.new
                   )
                 end
    end

    def deactivate_priority_sampling!(base_sampler = nil)
      @sampler = base_sampler || Datadog::AllSampler.new if @sampler.is_a?(PrioritySampler)
    end
  end
end
