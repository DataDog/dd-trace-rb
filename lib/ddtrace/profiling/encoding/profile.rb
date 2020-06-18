require 'set'

require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/pprof/template'

module Datadog
  module Profiling
    module Encoding
      module Profile
        # Encodes events to pprof
        module Protobuf
          DEFAULT_ENCODING = 'UTF-8'.freeze

          module_function

          def encode(flushes)
            return if flushes.empty?

            # Create a pprof template from the list of event types
            event_classes = flushes.collect(&:event_class).uniq
            template = Pprof::Template.for_event_classes(event_classes)

            # Add all events to the pprof
            flushes.each { |flush| template.add_events!(flush.event_class, flush.events) }

            # Build the profile and encode it
            template.to_encoded_profile
          end
        end
      end
    end
  end
end
