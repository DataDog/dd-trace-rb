# typed: true
require 'ddtrace/ext/distributed'
require 'ddtrace/trace_flush'

module Datadog
  module CI
    module TraceFlush
      # Common behavior for CI flushing
      module Tagging
        # Decorate a trace with CI tags
        def get_trace(trace_op)
          trace = trace_op.flush!

          # Origin tag is required on every span
          trace.spans.each do |span|
            span.set_tag(
              Datadog::Ext::DistributedTracing::TAG_ORIGIN,
              trace.origin
            )
          end

          trace
        end
      end

      # Consumes only completed traces (where all spans have finished)
      class Finished < Datadog::TraceFlush::Finished
        prepend Tagging
      end

      # Performs partial trace flushing to avoid large traces residing in memory for too long
      class Partial < Datadog::TraceFlush::Partial
        prepend Tagging
      end
    end
  end
end
