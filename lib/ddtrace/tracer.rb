require 'pp'
require 'thread'
require 'logger'

require 'ddtrace/span'
require 'ddtrace/buffer'
require 'ddtrace/writer'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Tracer keeps track of the time spent by an application processing a single operation. For
  # example, a trace can be used to track the entire time spent processing a complicated web request.
  # Even though the request may require multiple resources and machines to handle the request, all
  # of these function calls and sub-requests would be encapsulated within a single trace.
  class Tracer
    attr_reader :writer, :services
    attr_accessor :enabled

    # Global, memoized, lazy initialized instance of a logger that is used within the the Datadog
    # namespace. This logger outputs to +STDOUT+ by default, and is considered thread-safe.
    def self.log
      unless defined? @logger
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::INFO
      end
      @logger
    end

    # Activate the debug mode providing more information related to tracer usage
    def self.debug_logging=(value)
      log.level = value ? Logger::DEBUG : Logger::INFO
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
      @buffer = Datadog::SpanBuffer.new()

      @mutex = Mutex.new
      @spans = []
      @services = {}
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

      @enabled = enabled unless enabled.nil?
      @writer.transport.hostname = hostname unless hostname.nil?
      @writer.transport.port = port unless port.nil?
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
      spans = []
      @mutex.synchronize do
        @spans << span
        parent = span.parent
        @buffer.set(parent)

        return unless parent.nil?
        spans = @spans
        @spans = []
      end

      return if spans.empty?
      write(spans)
    end

    # Return the current active span or +nil+.
    def active_span
      @buffer.get()
    end
    # stats returns a dictionary of stats about the writer.
    def stats
      {
        spans: @spans.length()
      }
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
