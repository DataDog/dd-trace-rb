module Datadog
  # Pipeline
  module Pipeline
    require_relative 'pipeline/span_filter'
    require_relative 'pipeline/span_processor'

    @mutex = Mutex.new
    @processors = []

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
          .select(&:any?)
      end
    end

    def self.processors=(value)
      @processors = value
    end

    def self.apply_processors!(trace)
      result = @processors.inject(trace) do |current_trace, processor|
        processor.call(current_trace)
      end

      result || []
    rescue => e
      Datadog.logger.debug(
        "trace dropped entirely due to `Pipeline.before_flush` error: #{e}"
      )

      []
    end

    private_class_method :apply_processors!
  end
end
