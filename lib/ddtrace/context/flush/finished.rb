module Datadog
  class Context
    module Flush
      # Consumes only completed traces (where all spans have finished)
      class Finished
        # @return [Array<Span>] trace to be flushed, or +nil+ if the trace is not finished
        def consume(context)
          trace, sampled = context.get
          trace if sampled
        end
      end
    end
  end
end
