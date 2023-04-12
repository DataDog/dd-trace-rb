require 'time'

require_relative '../pprof/template'

module Datadog
  module Profiling
    module Encoding
      module Profile
        # Encodes gathered data into the pprof format
        module Protobuf
          module_function

          def encode(event_count:, event_groups:, start:, finish:)
            # Create a pprof template from the list of event types
            event_classes = event_groups.collect(&:event_class).uniq
            template = Pprof::Template.for_event_classes(event_classes)

            # Add all events to the pprof
            event_groups.each { |event_group| template.add_events!(event_group.event_class, event_group.events) }

            Datadog.logger.debug do
              max_events = Datadog.configuration.profiling.advanced.max_events
              events_sampled =
                if event_count == max_events
                  'max events limit hit, events were sampled [profile will be biased], '
                else
                  ''
                end

              "Encoding profile covering #{start.iso8601} to #{finish.iso8601}, " \
              "events: #{event_count} (#{events_sampled}#{template.debug_statistics})"
            end

            # Build the profile and encode it
            template.to_pprof(start: start, finish: finish)
          end
        end
      end
    end
  end
end
