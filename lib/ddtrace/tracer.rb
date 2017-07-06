require 'pp'
require 'thread'
require 'logger'
require 'pathname'

require 'ddtrace/span'
require 'ddtrace/context'
require 'ddtrace/provider'
require 'ddtrace/logger'
require 'ddtrace/writer'
require 'ddtrace/sampler'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Tracer keeps track of the time spent by an application processing a single operation. For
  # example, a trace can be used to track the entire time spent processing a complicated web request.
  # Even though the request may require multiple resources and machines to handle the request, all
  # of these function calls and sub-requests would be encapsulated within a single trace.
  # rubocop:disable Metrics/ClassLength
  class Tracer
    attr_reader :writer, :sampler, :services, :tags
    attr_accessor :enabled
    attr_writer :default_service

    # Global, memoized, lazy initialized instance of a logger that is used within the the Datadog
    # namespace. This logger outputs to +STDOUT+ by default, and is considered thread-safe.
    def self.log
      unless defined? @logger
        @logger = Datadog::Logger.new(STDOUT)
        @logger.level = Logger::WARN
      end
      @logger
    end

    # Override the default logger with a custom one.
    def self.log=(logger)
      return unless logger
      return unless logger.respond_to? :methods
      return unless logger.respond_to? :error
      if logger.respond_to? :methods
        unimplemented = Logger.new(STDOUT).methods - logger.methods
        unless unimplemented.empty?
          logger.error("logger #{logger} does not implement #{unimplemented}")
          return
        end
      end
      @logger = logger
    end

    # Activate the debug mode providing more information related to tracer usage
    def self.debug_logging=(value)
      log.level = value ? Logger::DEBUG : Logger::WARN
    end

    # Return if the debug mode is activated or not
    def self.debug_logging
      log.level == Logger::DEBUG
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

      @mutex = Mutex.new
      @services = {}
      @tags = {}
    end

    # Updates the current \Tracer instance, so that the tracer can be configured after the
    # initialization. Available +options+ are:
    #
    # * +enabled+: set if the tracer submits or not spans to the trace agent
    # * +hostname+: change the location of the trace agent
    # * +port+: change the port of the trace agent
    #
    # For instance, if the trace agent runs in a different location, just:
    #
    #   tracer.configure(hostname: 'agent.service.consul', port: '8777')
    #
    def configure(options = {})
      enabled = options.fetch(:enabled, nil)
      hostname = options.fetch(:hostname, nil)
      port = options.fetch(:port, nil)
      sampler = options.fetch(:sampler, nil)

      @enabled = enabled unless enabled.nil?
      @writer.transport.hostname = hostname unless hostname.nil?
      @writer.transport.port = port unless port.nil?
      @sampler = sampler unless sampler.nil?
    end

    # Set the information about the given service. A valid example is:
    #
    #   tracer.set_service_info('web-application', 'rails', 'web')
    def set_service_info(service, app, app_type)
      @services[service] = {
        'app' => app,
        'app_type' => app_type
      }

      return unless Datadog::Tracer.debug_logging
      Datadog::Tracer.log.debug("set_service_info: service: #{service} app: #{app} type: #{app_type}")
    end

    # A default value for service. One should really override this one
    # for non-root spans which have a parent. However, root spans without
    # a service would be invalid and rejected.
    def default_service
      return @default_service if instance_variable_defined?(:@default_service) && @default_service
      begin
        @default_service = File.basename($PROGRAM_NAME, '.*')
      rescue => e
        Datadog::Tracer.log.error("unable to guess default service: #{e}")
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

    # Return a span that will trace an operation called \name. This method allows
    # parenting passing \child_of as an option. If it's missing, the newly created span is a
    # root span. Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or \name if it's missing
    # * +span_type+: the type of the span (such as \http, \db and so on)
    # * +parent_id+: the identifier of the parent span
    # * +trace_id+: the identifier of the root span for this trace
    # * +child_of+: a \Span or a \Context instance representing the parent for this span.
    # * +start_time+: when the span actually starts (defaults to \now)
    # * +tags+: extra tags which should be added to the span.
    def start_span(name, options = {})
      start_time = options.fetch(:start_time, Time.now.utc)
      child_of = options.fetch(:child_of, nil) # can be context or span
      tags = options.fetch(:tags, {})

      unless child_of.nil?
        if child_of.respond_to?(:current_span)
          ctx = child_of
          parent = ctx.current_span
        end
        parent = child_of if child_of.is_a?(Datadog::Span)
      end
      ctx ||= call_context
      parent ||= ctx.current_span
      opts = {
        context: ctx
      }
      opts.merge!(options)
      if parent.nil?
        # root span
        span = Span.new(self, name, opts)
        @sampler.sample(span)
      else
        # child span
        opts[:service] ||= parent.service
        opts[:trace_id] = parent.trace_id
        opts[:parent_id] = parent.span_id
        span = Span.new(self, name, opts)
        span.parent = parent
        span.sampled = parent.sampled
      end
      tags.each { |k, v| span.set_tag(k, v) } unless tags.empty?
      @tags.each { |k, v| span.set_tag(k, v) } unless @tags.empty?
      span.start_time = start_time
      ctx.add_span(span)
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
    # This method accepts all the options accepted by \start_span.
    def trace(name, options = {})
      span = start_span(name, options)

      # call the finish only if a block is given; this ensures
      # that a call to tracer.trace() without a block, returns
      # a span that should be manually finished.
      if block_given?
        begin
          yield(span)
        rescue StandardError => e
          span.set_error(e)
          raise
        ensure
          span.finish()
        end
      else
        span
      end
    end

    # Record the given +context+. For compatibility with previous versions,
    # +context+ can also be a span. It is similar to the +child_of+ argument,
    # method will figure out what to do, submitting a +span+ for recording
    # is like trying to record its +context+.
    def record(context)
      context = context.context if context.is_a?(Datadog::Span)
      return if context.nil?
      trace, sampled = context.get
      ready = !trace.nil? && !trace.empty? && sampled
      write(trace) if ready
    end

    # Return the current active span or +nil+.
    def active_span
      call_context.current_span
    end

    # Send the trace to the writer to enqueue the spans list in the agent
    # sending queue.
    def write(trace)
      return if @writer.nil? || !@enabled

      if Datadog::Tracer.debug_logging
        Datadog::Tracer.log.debug("Writing #{trace.length} spans (enabled: #{@enabled})")
        PP.pp(trace)
      end

      @writer.write(trace, @services)
    end

    private :write
  end
end
