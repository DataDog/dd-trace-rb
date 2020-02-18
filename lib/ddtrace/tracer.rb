require 'pp'
require 'thread'
require 'logger'
require 'pathname'

require 'ddtrace/span'
require 'ddtrace/context'
require 'ddtrace/logger'
require 'ddtrace/writer'
require 'ddtrace/sampler'
require 'ddtrace/sampling'
require 'ddtrace/correlation'

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
    DEFAULT_ON_ERROR = proc { |span, error| span.set_error(error) unless span.nil? }

    def services
      # Only log each deprecation warning once (safeguard against log spam)
      Datadog::Patcher.do_once('Tracer#set_service_info') do
        Datadog::Logger.log.warn('services: Usage of Tracer.services has been deprecated')
      end

      {}
    end

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
    def call_context
      @provider.context
    end

    # Initialize a new \Tracer used to create, sample and submit spans that measure the
    # time of sections of code. Available +options+ are:
    #
    # * +enabled+: set if the tracer submits or not spans to the local agent. It's enabled
    #   by default.
    def initialize(options = {})
      @enabled = options.fetch(:enabled, true)
      @writer = options.fetch(:writer, Datadog::Writer.new)
      @sampler = options.fetch(:sampler, Datadog::AllSampler.new)

      @provider = options.fetch(:context_provider, Datadog::DefaultContextProvider.new)
      @provider ||= Datadog::DefaultContextProvider.new # @provider should never be nil

      @context_flush = if options[:partial_flush]
                         Datadog::ContextFlush::Partial.new(options)
                       else
                         Datadog::ContextFlush::Finished.new
                       end

      @mutex = Mutex.new
      @tags = {}

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

      @context_flush = if options[:partial_flush]
                         Datadog::ContextFlush::Partial.new(options)
                       else
                         Datadog::ContextFlush::Finished.new
                       end
    end

    # Set the information about the given service. A valid example is:
    #
    #   tracer.set_service_info('web-application', 'rails', 'web')
    #
    # set_service_info is deprecated, no service information needs to be tracked
    def set_service_info(service, app, app_type)
      # Only log each deprecation warning once (safeguard against log spam)
      Datadog::Patcher.do_once('Tracer#set_service_info') do
        Datadog::Logger.log.warn(%(
          set_service_info: Usage of set_service_info has been deprecated,
          service information no longer needs to be reported to the trace agent.
        ))
      end
    end

    # A default value for service. One should really override this one
    # for non-root spans which have a parent. However, root spans without
    # a service would be invalid and rejected.
    def default_service
      return @default_service if instance_variable_defined?(:@default_service) && @default_service
      begin
        @default_service = File.basename($PROGRAM_NAME, '.*')
      rescue StandardError => e
        Datadog::Logger.log.error("unable to guess default service: #{e}")
        @default_service = 'ruby'.freeze
      end
      @default_service
    end

    # Set the given key / value tag pair at the tracer level. These tags will be
    # appended to each span created by the tracer. Keys and values must be strings.
    # A valid example is:
    #
    #   tracer.set_tags('env' => 'prod', 'component' => 'core')
    def set_tags(tags)
      @tags.update(tags)
    end

    # Guess context and parent from child_of entry.
    def guess_context_and_parent(child_of)
      # call_context should not be in this code path, as start_span
      # should never try and pick an existing context, but only get
      # it from the parameters passed to it (child_of)
      return [Datadog::Context.new, nil] unless child_of

      return [child_of, child_of.current_span] if child_of.is_a?(Context)

      [child_of.context, child_of]
    end

    # Return a span that will trace an operation called \name. This method allows
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
      start_time = options.fetch(:start_time, Time.now.utc)

      tags = options.fetch(:tags, {})

      span_options = options.select do |k, _v|
        # Filter options, we want no side effects with unexpected args.
        ALLOWED_SPAN_OPTIONS.include?(k)
      end

      ctx, parent = guess_context_and_parent(options[:child_of])
      span_options[:context] = ctx unless ctx.nil?

      span = Span.new(self, name, span_options)
      if parent.nil?
        # root span
        @sampler.sample!(span)
        span.set_tag('system.pid', Process.pid)

        if ctx && ctx.trace_id
          span.trace_id = ctx.trace_id
          span.parent_id = ctx.span_id unless ctx.span_id.nil?
        end
      else
        # child span
        span.parent = parent # sets service, trace_id, parent_id, sampled
      end
      tags.each { |k, v| span.set_tag(k, v) } unless tags.empty?
      @tags.each { |k, v| span.set_tag(k, v) } unless @tags.empty?
      span.start_time = start_time

      # this could at some point be optional (start_active_span vs start_manual_span)
      ctx.add_span(span) unless ctx.nil?

      span
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
    # * +tags+: extra tags which should be added to the span.
    def trace(name, options = {})
      options[:child_of] = call_context

      # call the finish only if a block is given; this ensures
      # that a call to tracer.trace() without a block, returns
      # a span that should be manually finished.
      if block_given?
        span = nil
        return_value = nil

        begin
          begin
            span = start_span(name, options)
          # rubocop:disable Lint/UselessAssignment
          rescue StandardError => e
            Datadog::Logger.log.debug('Failed to start span: #{e}')
          ensure
            return_value = yield(span)
          end
        # rubocop:disable Lint/RescueException
        # Here we really want to catch *any* exception, not only StandardError,
        # as we really have no clue of what is in the block,
        # and it is user code which should be executed no matter what.
        # It's not a problem since we re-raise it afterwards so for example a
        # SignalException::Interrupt would still bubble up.
        rescue Exception => e
          (options[:on_error] || DEFAULT_ON_ERROR).call(span, e)
          raise e
        ensure
          span.finish unless span.nil?
        end

        return_value
      else
        start_span(name, options)
      end
    end

    # Record the given +context+. For compatibility with previous versions,
    # +context+ can also be a span. It is similar to the +child_of+ argument,
    # method will figure out what to do, submitting a +span+ for recording
    # is like trying to record its +context+.
    def record(context)
      context = context.context if context.is_a?(Datadog::Span)
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

      write(trace) if trace && !trace.empty?
    end

    # Return the current active span or +nil+.
    def active_span
      call_context.current_span
    end

    # Return the current active root span or +nil+.
    def active_root_span
      call_context.current_root_span
    end

    # Return a CorrelationIdentifier for active span
    def active_correlation
      Datadog::Correlation.identifier_from_context(call_context)
    end

    # Send the trace to the writer to enqueue the spans list in the agent
    # sending queue.
    def write(trace)
      return if @writer.nil? || !@enabled

      if Datadog::Logger.debug_logging
        Datadog::Logger.log.debug("Writing #{trace.length} spans (enabled: #{@enabled})")
        str = String.new('')
        PP.pp(trace, str)
        Datadog::Logger.log.debug(str)
      end

      @writer.write(trace)
    end

    # TODO: Move this kind of configuration building out of the tracer.
    #       Tracer should not have this kind of knowledge of writer.
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/MethodLength
    def configure_writer(options = {})
      hostname = options.fetch(:hostname, nil)
      port = options.fetch(:port, nil)
      sampler = options.fetch(:sampler, nil)
      priority_sampling = options.fetch(:priority_sampling, nil)
      writer = options.fetch(:writer, nil)
      transport_options = options.fetch(:transport_options, {})

      # Compile writer options
      writer_options = options.fetch(:writer_options, {})
      rebuild_writer = !writer_options.empty?

      # Re-build the sampler and writer if priority sampling is enabled,
      # but neither are configured. Verify the sampler isn't already a
      # priority sampler too, so we don't wrap one with another.
      if options.key?(:writer)
        if writer.respond_to?(:priority_sampler)
          if writer.priority_sampler.nil?
            deactivate_priority_sampling!(sampler)
          else
            activate_priority_sampling!(writer.priority_sampler)
          end
        end
      elsif priority_sampling != false && !@sampler.is_a?(PrioritySampler)
        writer_options[:priority_sampler] = activate_priority_sampling!(@sampler)
        rebuild_writer = true
      elsif priority_sampling == false
        deactivate_priority_sampling!(sampler)
        rebuild_writer = true
      elsif @sampler.is_a?(PrioritySampler)
        # Make sure to add sampler to options if transport is rebuilt.
        writer_options[:priority_sampler] = @sampler
      end

      # Apply options to transport
      if transport_options.is_a?(Proc)
        transport_options = { on_build: transport_options }
        rebuild_writer = true
      end

      if hostname || port
        transport_options[:hostname] = hostname unless hostname.nil?
        transport_options[:port] = port unless port.nil?
        rebuild_writer = true
      end

      writer_options[:transport_options] = transport_options

      if rebuild_writer || writer
        # Make sure old writer is shut down before throwing away.
        # Don't want additional threads running...
        @writer.stop unless writer.nil?
        @writer = writer || Writer.new(writer_options)
      end
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
      :record_context,
      :write
  end
end
