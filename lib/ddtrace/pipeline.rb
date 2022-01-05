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
    #
    # @see file:docs/ProcessingPipeline.md Processing Pipeline
    # @param [Array<Proc>] processors a list of callable objects that receive a list of {Datadog::Span}s and can modify
    #   or filter our spans.
    # @yield Optional that receives an array of spans and returns the desired remaining spans.
    # @yieldparam [Array<Datadog::Span>] spans spans that can be modified or removed from list before flushing.
    # @yieldreturn [Array<Datadog::Span>] an array of spans to be kept. An empty array means all spans were dropped.
    def self.before_flush(*processors, &processor_block)
      processors = [processor_block] if processors.empty?

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
