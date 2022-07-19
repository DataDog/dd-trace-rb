require 'datadog/tracing/stats/repository'

module Datadog
  module Tracing
    module Stats
      # TOP-LEVEL class description
      class NullComputer
        def perform(_); end
      end

      # TOP-LEVEL class description
      class Computer
        # include Core::Workers::Async::Thread

        attr_reader :repository

        def initialize
          @repository = Repository.new
        end

        # Asynchronously
        def perform(trace_segment)
          origin = trace_segment.origin
          candidates = trace_segment.spans.select do |span|
            span.__send__(:service_entry?) ||
              span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED) == 1
          end

          candidates.each do |span|
            bucket_size_ns = 10 * 1e9
            bucket_time_ns = span.end_time_nano - (span.end_time_nano % bucket_size_ns)

            # memory issue
            agg_key = [
              span.name,
              span.service,
              span.resource, # obfuscate
              span.type,
              span.status,
              origin == 'synthetics'
            ]

            repository.update!(bucket_time_ns, agg_key, span)
          end
        end
      end
    end
  end
end
