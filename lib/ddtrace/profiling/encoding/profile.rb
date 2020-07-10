require 'set'

require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/pprof/template'

module Datadog
  module Profiling
    module Encoding
      module Profile
        # Encodes events to pprof
        module Protobuf
          module_function

          def encode(flush)
            return unless flush

            # Create a pprof template from the list of event types
            event_classes = flush.event_groups.collect(&:event_class).uniq
            template = Pprof::Template.for_event_classes(event_classes)

            # Add all events to the pprof
            flush.event_groups.each { |event_group| template.add_events!(event_group.event_class, event_group.events) }

            # Build the profile and encode it
            template.to_encoded_profile
          end
        end
      end
    end
  end
end
