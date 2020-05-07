require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/stack_sample'

module Datadog
  module Profiling
    module Encoding
      module Profile
        # Encodes events to pprof
        module Protobuf
          module_function

          def encode(events)
            return if events.empty?

            builder = case events.first
                      when Profiling::Events::StackSample
                        Pprof::StackSample.new(events)
                      else
                        raise UnknownEventTypeError, events.first.class
                      end

            profile = builder.to_profile
            Perftools::Profiles::Profile.encode(profile)
          end

          # Error when an unknown event type is given to be encoded
          class UnknownEventTypeError < ArgumentError
            attr_reader :type

            def initialize(type)
              @type = type
            end

            def message
              "Unknown event type cannot be encoded to pprof: #{type}"
            end
          end
        end
      end
    end
  end
end
