require 'set'
require 'time'

require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/pprof/template'

module Datadog
  module Profiling
    module Encoding
      module Profile
        # Encodes gathered data into the pprof format
        module Protobuf
          module_function

          def encode(flush)
            return unless flush

            # Create a pprof template from the list of event types
            event_classes = flush.event_groups.collect(&:event_class).uniq
            template = Pprof::Template.for_event_classes(event_classes)

            # Add all events to the pprof
            flush.event_groups.each { |event_group| template.add_events!(event_group.event_class, event_group.events) }

            Datadog.logger.debug do
              "Encoding profile covering #{flush.start.iso8601} to #{flush.finish.iso8601}, " \
              "events: #{flush.event_count} (#{template.debug_statistics})"
            end

            # Build the profile and encode it
            template.to_pprof
          end
        end
      end
    end
  end
end
