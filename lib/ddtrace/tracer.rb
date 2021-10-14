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
    attr_reader :sampler, :tags, :provider, :context_flush
    attr_accessor :enabled, :writer
    attr_writer :default_service

    ALLOWED_SPAN_OPTIONS = [:service, :resource, :span_type].freeze

    # Shorthand that calls the `shutdown!` method of a registered worker.
    # It's useful to ensure that the Trace Buffer is properly flushed before
    # shutting down the application.
    #
    # For instance:
    #
    #   tracer.trace('operation_name', service='rake_tasks') do |span|
    #     span.set_tag('task.name', 'script')
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

    # Guess context and parent from child_of entry.
    def guess_context_and_parent(child_of)
      case child_of
      when Context
        [child_of, child_of.current_span]
      when SpanOperation
        [child_of.context, child_of]
      when Span
        [nil, child_of]
      else
        # Start of a trace
        [Context.new, nil]
      end
    end

    # Build a span that will trace an operation called \name. This method allows
    # parenting passing \child_of as an option. If it's missing, the newly created span is a
    # root span. Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or \name if it's missing
    # * +span_type+: the type of the span (such as \http, \db and so on)
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    # * +tags+: extra tags which should be added to the span.
    def build_span(name, options = {})
      # Resolve context, parent
      context, parent = guess_context_and_parent(options[:child_of])

      # Build span options
      options[:context] = context
      options[:child_of] = parent
      options[:service] ||= (parent && parent.service) || default_service
      options[:tags] =  if @tags.any? && options[:tags]
                          # Combine default tags with provided tags,
                          # preferring provided tags.
                          @tags.merge(options[:tags])
                        else
                          # Use provided tags or default tags if none.
                          options[:tags] || @tags.dup
                        end

      # Build a new span operation
      span = Datadog::SpanOperation.new(name, options)

      # Subscribe to events
      span.events.after_finish.subscribe(:tracer_span_finished) do |span_op|
        record_span(span_op)
      end

      # Wrap default error behavior with custom handler if provided
      if options[:on_error].respond_to?(:call)
        span.events.on_error.wrap(:default) do |original, span_op, error|
          begin
            options[:on_error].call(span_op, error)
          rescue StandardError => e
            Datadog.logger.debug(
              "Custom on_error handler failed, using fallback behavior. \
               Error: #{e.message} Location: #{e.backtrace.first}"
            )
            original.call(span_op, error) if original
          end
        end
      end

      # If it's a root span...
      @sampler.sample!(span) if parent.nil?

      span
    end

    # Build and start a span that will trace an operation called \name. This method allows
    # parenting passing \child_of as an option. If it's missing, the newly created span is a
    # root span. Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or \name if it's missing
    # * +span_type+: the type of the span (such as \http, \db and so on)
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    # * +start_time+: when the span actually starts (defaults to \now)
    # * +tags+: extra tags which should be added to the span.
    def start_span(name, options = {})
      span = build_span(name, options)
      span.start(options[:start_time])
      span
    end

    # Records the span (& its context)
    def record_span(operation)
      begin
        operation.service ||= default_service
        record_context(operation.context) if operation.context
        operation.span
      rescue StandardError => e
        Datadog.logger.debug("Error recording finished trace: #{e} Backtrace: #{e.backtrace.first}")
        Datadog.health_metrics.error_span_finish(1, tags: ["error:#{e.class.name}"])
      end
    end

    # Return a +span+ that will trace an operation called +name+. You could trace your code
    # using a <tt>do-block</tt> like:
    #
    #   tracer.trace('web.request') do |span|
    #     span.service = 'my-web-site'
    #     span.resource = '/'
    #     span.set_tag('http.method', request.request_method)
    #     do_something()
    #   end
    #
    # The <tt>tracer.trace()</tt> method can also be used without a block in this way:
    #
    #   span = tracer.trace('web.request', service: 'my-web-site')
    #   do_something()
    #   span.finish()
    #
    # Remember that in this case, calling <tt>span.finish()</tt> is mandatory.
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
    # * +span_type+: the type of the span (such as \http, \db and so on)
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    #   If not set, defaults to Tracer.call_context
    # * +tags+: extra tags which should be added to the span.
    def trace(name, options = {}, &block)
      options[:child_of] ||= call_context

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
          span = build_span(name, options)
        rescue StandardError => e
          Datadog.logger.debug("Failed to build span: #{e}")
          yield(nil)
        else
          span.measure(&block)
        end
      else
        start_span(name, options)
      end
    end

    def trace_completed
      @trace_completed ||= TraceCompleted.new
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

    private \
      :activate_priority_sampling!,
      :configure_writer,
      :deactivate_priority_sampling!,
      :guess_context_and_parent,
      :record_span,
      :record_context,
      :write
  end
end
