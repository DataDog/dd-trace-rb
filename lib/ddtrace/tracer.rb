require 'ddtrace/span'
require 'ddtrace/buffer'
require 'ddtrace/writer'

module Datadog
  # Tracer class that records and creates spans related to a
  # compositions of logical units of work.
  class Tracer
    attr_reader :writer

    def initialize(options = {})
      # buffers and sends completed traces.
      @writer = options.fetch(:writer, Datadog::Writer.new())

      # store thes the active thread in the current span.
      @buffer = Datadog::SpanBuffer.new()
      @spans = []
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
      @spans << span
      parent = span.parent
      @buffer.set(parent)

      return unless parent.nil?
      spans = @spans
      @spans = []
      write(spans)
    end

    def write(spans)
      @writer.write(spans) unless @writer.nil?
    end

    def active_span
      @buffer.get
    end
  end
end
