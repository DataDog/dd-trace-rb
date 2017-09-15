require 'ddtrace/tracer'
require 'concurrent'

module Datadog
  class TestTracer < Tracer
    attr_reader :traces

    def initialize(options = {})
      @traces = Concurrent::Array.new
      super(options.merge(enabled: false))
    end

    def reset!
      @traces.clear
    end

    def write(trace)
      @traces << trace
      super
    end
  end
end
