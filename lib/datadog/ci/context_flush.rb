require 'ddtrace/context_flush'

module Datadog
  module CI
    module ContextFlush
      # Common behavior for CI flushing
      module Tagging
        # Decorate a trace with CI tags
        def get_trace(context)
          context.get do |trace|
            # Origin tag is required on every span
            trace.each { |span| context.attach_origin(span) } if trace
          end
        end
      end

      # Consumes only completed traces (where all spans have finished)
      class Finished < Datadog::ContextFlush::Finished
        prepend Tagging
      end

      # Performs partial trace flushing to avoid large traces residing in memory for too long
      class Partial < Datadog::ContextFlush::Partial
        prepend Tagging
      end
    end
  end
end
