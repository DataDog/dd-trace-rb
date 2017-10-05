module Datadog
  # FilterPipeline handles trace filtering based on user-defined filters
  class FilterPipeline
    def initialize
      @mutex = Mutex.new
      @filters = []
    end

    def call(trace)
      @mutex.synchronize do
        black_list = trace.select { |span| drop_it?(span) }

        clean_trace(black_list, trace) while black_list.any?

        trace
      end
    end

    def add_filter(filter = nil, &block)
      callable = filter || block

      raise(ArgumentError) unless callable.respond_to?(:call)

      @mutex.synchronize { @filters << callable }
    end

    private

    def drop_it?(span)
      @filters.any? do |filter|
        filter.call(span) rescue false
      end
    end

    def clean_trace(black_list, trace)
      current = black_list.shift

      trace.delete(current)

      trace.each do |span|
        black_list << span if span.parent == current
      end
    end
  end
end
