# typed: true
module Datadog
  # Pipeline
  # @public_api
  module Pipeline
    require_relative 'pipeline/span_filter'
    require_relative 'pipeline/span_processor'

    @mutex = Mutex.new
    @processors = []

    # {.before_flush} allows application to alter or filter out traces before they are flushed.
    # If both `processors` and `processor_block` are provided, both are added to the internal
    # processors list, with `processor_block` being added after `processors`.
    #
    # @see file:docs/GettingStarted.md#processing-pipeline Processing Pipeline
    #
    # @overload before_flush(*processors)
    #   @param [Array<Datadog::Pipeline::SpanProcessor>] processors a list of processors that can modify
    #     or filter the trace.
    #   @param [Array<#call(Datadog::TraceSegment)>] processors a list of callable objects that receive a
    #     {Datadog::TraceSegment} and can modify or filter the trace.
    # @overload before_flush(&processor_block)
    #   @yield Receive a {Datadog::TraceSegment} and can modify or filter the trace.
    #   @yieldparam [Datadog::TraceSegment] trace trace object that can be modified or filtered.
    #   @yieldreturn [Datadog::TraceSegment] the trace object that will be passed to the next processor. Normally
    #     the same `trace` parameter object should be returned.
    def self.before_flush(*processors, &processor_block)
      processors << processor_block if processor_block

      @mutex.synchronize do
        @processors.concat(processors)
      end
    end

    def self.process!(traces)
      @mutex.synchronize do
        traces
          .map(&method(:apply_processors!))
          .compact
      end
    end

    def self.processors=(value)
      @processors = value
    end

    def self.apply_processors!(trace)
      @processors.inject(trace) do |current_trace, processor|
        next nil if current_trace.nil? || current_trace.empty?

        process_result = processor.call(current_trace)
        process_result && process_result.empty? ? nil : process_result
      end
    rescue => e
      Datadog.logger.debug(
        "trace dropped entirely due to `Pipeline.before_flush` error: #{e}"
      )

      nil
    end

    private_class_method :apply_processors!
  end
end
