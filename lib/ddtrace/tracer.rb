require 'pp'
require 'thread'
require 'logger'
require 'pathname'

require 'ddtrace/span'
require 'ddtrace/buffer'
require 'ddtrace/logger'
require 'ddtrace/writer'
require 'ddtrace/sampler'

# Default tags used when initializing the tracer
DEFAULT_TAGS = {
  'lang' => 'ruby',
  'lang.version' => RUBY_VERSION
}.freeze

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Tracer keeps track of the time spent by an application processing a single operation. For
  # example, a trace can be used to track the entire time spent processing a complicated web request.
  # Even though the request may require multiple resources and machines to handle the request, all
  # of these function calls and sub-requests would be encapsulated within a single trace.
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

    # Initialize a new \Tracer used to create, sample and submit spans that measure the
    # time of sections of code. Available +options+ are:
    #
    # * +enabled+: set if the tracer submits or not spans to the local agent. It's enabled
    #   by default.
    def initialize(options = {})
      @enabled = options.fetch(:enabled, true)
      @writer = options.fetch(:writer, Datadog::Writer.new)
      @sampler = options.fetch(:sampler, Datadog::AllSampler.new)

      @buffer = Datadog::SpanBuffer.new()

      @mutex = Mutex.new
      @spans = []
      @services = {}
      @tags = DEFAULT_TAGS
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
      return @default_service if @default_service
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
    def trace(name, options = {})
      span = Span.new(self, name, options)

      # set up inheritance
      parent = @buffer.get()
      span.set_parent(parent)
      @buffer.set(span)

      @tags.each { |k, v| span.set_tag(k, v) } unless @tags.empty?

      # sampling
      if parent.nil?
        @sampler.sample(span)
      else
        span.sampled = span.parent.sampled
      end

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

    # Record the given finished span in the +spans+ list. When a +span+ is recorded, it will be sent
    # to the Datadog trace agent as soon as the trace is finished.
    def record(span)
      span.service ||= default_service

      spans = []
      @mutex.synchronize do
        @spans << span
        parent = span.parent
        # Bubble up until we find a non-finished parent. This is necessary for
        # the case when the parent finished after its parent.
        parent = parent.parent while !parent.nil? && parent.finished?
        @buffer.set(parent)

        return unless parent.nil?

        # In general, all spans within the buffer belong to the same trace.
        # But in heavily multithreaded contexts and/or when using lots of callbacks
        # hooks and other non-linear programming style, one can technically
        # end up in different situations. So we only extract the spans which
        # are associated to the root span that just finished, and save the
        # others for later.
        trace_spans = []
        alien_spans = []
        @spans.each do |s|
          if s.trace_id == span.trace_id
            trace_spans << s
          else
            alien_spans << s
          end
        end
        spans = trace_spans
        @spans = alien_spans
      end

      return if spans.empty? || !span.sampled
      write(spans)
    end

    # Return the current active span or +nil+.
    def active_span
      @buffer.get()
    end

    def write(spans)
      return if @writer.nil? || !@enabled

      if Datadog::Tracer.debug_logging
        Datadog::Tracer.log.debug("Writing #{spans.length} spans (enabled: #{@enabled})")
        PP.pp(spans)
      end

      @writer.write(spans, @services)
    end

    private :write
  end
end
