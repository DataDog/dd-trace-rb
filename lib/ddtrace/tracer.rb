require 'thread'
require 'logger'

require 'ddtrace/span'
require 'ddtrace/buffer'
require 'ddtrace/writer'

module Datadog
  # Tracer class that records and creates spans related to a
  # compositions of logical units of work.
  class Tracer
    attr_reader :writer, :services
    attr_accessor :enabled

    # global, memoized, lazy initialized instance of a logger
    # TODO[manu]: used only to have a common way to log things among
    # the tracer. Don't know if users may want to replace the internal
    # logger with their own
    def self.log
      unless defined? @logger
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::INFO
      end
      @logger
    end

    def initialize(options = {})
      @enabled = options.fetch(:enabled, true)
      @writer = options.fetch(:writer, Datadog::Writer.new)
      @buffer = Datadog::SpanBuffer.new()

      @mutex = Mutex.new
      @spans = []
      @services = {}
    end

    def set_service_info(service, app, app_type)
      @services[service] = {
        'app' => app,
        'app_type' => app_type
      }
    end

    def trace(name, options = {})
      span = Span.new(self, name, options)

      # set up inheritance
      parent = @buffer.get()
      span.set_parent(parent)
      @buffer.set(span)

      # call the finish only if a block is given; this ensures
      # that a call to tracer.trace() without a block, returns
      # a span that should be manually finished.
      begin
        yield(span) if block_given?
      rescue StandardError => e
        span.set_error(e)
        raise
      ensure
        span.finish() if block_given?
      end

      span
    end

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

    def write(spans)
      return if @writer.nil? || !@enabled
      @writer.write(spans, @services)
    end

    def active_span
      @buffer.get()
    end
  end
end
